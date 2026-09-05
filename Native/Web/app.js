(() => {
  "use strict";

  const API_ROOT = "/api";
  const REQUEST_TIMEOUT_MS = 15000;

  const appList = document.getElementById("app-list");
  const feedback = document.getElementById("feedback");
  const refreshButton = document.getElementById("refresh-button");
  const authSection = document.getElementById("auth-section");
  const authForm = document.getElementById("auth-form");
  const tokenInput = document.getElementById("token-input");
  const connectionStatus = document.getElementById("connection-status");
  const connectionLabel = document.getElementById("connection-label");
  const lastUpdated = document.getElementById("last-updated");

  let accessToken = "";

  const state = {
    apps: [],
    pendingIDs: new Set(),
    catalogRequest: null,
  };

  class APIError extends Error {
    constructor(message, status = 0) {
      super(message);
      this.name = "APIError";
      this.status = status;
    }
  }

  function showAuth() {
    authSection.hidden = false;
    setConnection("locked", "Token required");
  }

  function hideAuth() {
    authSection.hidden = true;
    tokenInput.value = "";
  }

  function isUnauthorized(error) {
    return error instanceof APIError && (error.status === 401 || error.status === 403);
  }

  function clearCatalogForAuthFailure() {
    accessToken = "";
    state.apps = [];
    state.pendingIDs.clear();
    renderApps();
    showAuth();
  }

  function setConnection(status, label) {
    connectionStatus.dataset.state = status;
    connectionLabel.textContent = label;
  }

  function setFeedback(kind, title, message, actionLabel = "", actionHandler = null) {
    feedback.hidden = false;
    feedback.dataset.kind = kind;
    feedback.replaceChildren();

    const copy = document.createElement("div");
    copy.className = "feedback-copy";

    const titleElement = document.createElement("p");
    titleElement.className = "feedback-title";
    titleElement.textContent = title;
    copy.append(titleElement);

    if (message) {
      const messageElement = document.createElement("p");
      messageElement.className = "feedback-message";
      messageElement.textContent = message;
      copy.append(messageElement);
    }

    feedback.append(copy);

    if (actionLabel && actionHandler) {
      const action = document.createElement("button");
      action.className = "feedback-action";
      action.type = "button";
      action.textContent = actionLabel;
      action.addEventListener("click", actionHandler, { once: true });
      feedback.append(action);
    }
  }

  function clearFeedback() {
    feedback.hidden = true;
    feedback.replaceChildren();
  }

  function setRefreshBusy(isBusy) {
    refreshButton.disabled = isBusy;
    refreshButton.setAttribute("aria-busy", String(isBusy));
    refreshButton.querySelector("span").textContent = isBusy ? "Refreshing" : "Refresh";
  }

  function getErrorMessage(error, fallback) {
    if (error instanceof APIError) {
      if (error.message) return error.message;
      switch (error.status) {
        case 400:
          return "The request was not accepted. Refresh the catalog and try again.";
        case 404:
          return "That app is no longer registered. Refresh the catalog and try again.";
        case 409:
          return "The Mac could not change that app right now. Try again.";
        case 429:
          return "The Mac is busy. Wait a moment, then try again.";
        case 500:
        case 502:
        case 503:
          return "The Mac returned an error. Check the app, then retry.";
        default:
          return fallback;
      }
    }
    if (error instanceof TypeError) {
      return "The local API could not be reached. Check that the Mac app is running, then retry.";
    }
    return fallback;
  }

  async function requestJSON(path, options = {}) {
    if (!accessToken) {
      throw new APIError("Enter an access token to connect to the local API.", 401);
    }

    const controller = new AbortController();
    const timeoutID = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

    try {
      const response = await fetch(`${API_ROOT}${path}`, {
        ...options,
        signal: controller.signal,
        credentials: "omit",
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${accessToken}`,
          ...(options.headers || {}),
        },
      });

      const contentType = response.headers.get("content-type") || "";
      const payload = contentType.includes("application/json")
        ? await response.json()
        : null;

      if (!response.ok) {
        throw new APIError("", response.status);
      }

      return payload;
    } catch (error) {
      if (error && error.name === "AbortError") {
        throw new APIError("The request timed out. Check the local connection and retry.");
      }
      throw error;
    } finally {
      window.clearTimeout(timeoutID);
    }
  }

  function getString(value, fallback = "") {
    return typeof value === "string" && value.trim() ? value.trim() : fallback;
  }

  function getBoolean(value) {
    return typeof value === "boolean" ? value : null;
  }

  function normalizeApp(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      return null;
    }

    const keys = Object.keys(raw);
    if (keys.length !== 3 || keys.some((key) => !["id", "name", "running"].includes(key))) {
      return null;
    }

    const id = getString(raw.id);
    const name = getString(raw.name);
    if (!id || !name) {
      return null;
    }

    const running = getBoolean(raw.running);
    if (running === null) {
      return null;
    }

    return {
      id,
      name,
      running,
    };
  }

  function parseApps(payload) {
    const rawApps = payload && Array.isArray(payload.apps) ? payload.apps : null;

    if (!rawApps) {
      throw new APIError("The local API returned an unexpected app catalog.");
    }

    const apps = rawApps.map(normalizeApp);
    if (apps.some((app) => app === null)) {
      throw new APIError("The local API returned an unexpected app catalog.");
    }
    return apps;
  }

  function monogram(name) {
    const words = name.split(/\s+/).filter(Boolean);
    if (words.length > 1) {
      return `${words[0][0]}${words[1][0]}`.toUpperCase();
    }
    return name.slice(0, 2).toUpperCase();
  }

  function appStatusLabel(app) {
    if (app.running === true) return "Running";
    if (app.running === false) return "Not running";
    return "Status unavailable";
  }

  function renderApps() {
    appList.replaceChildren();
    appList.setAttribute("aria-busy", "false");

    if (state.apps.length === 0) {
      const empty = document.createElement("div");
      empty.className = "empty-state";

      const title = document.createElement("h3");
      title.textContent = "No apps are registered";
      empty.append(title);

      const message = document.createElement("p");
      message.textContent = "Register an app in Micro Launchpad on your Mac, then refresh this page.";
      empty.append(message);

      const action = document.createElement("button");
      action.className = "button button-secondary";
      action.type = "button";
      action.textContent = "Refresh catalog";
      action.addEventListener("click", loadApps);
      empty.append(action);

      appList.append(empty);
      return;
    }

    for (const app of state.apps) {
      const row = document.createElement("article");
      row.className = "app-row";
      row.dataset.appID = app.id;

      const identity = document.createElement("div");
      identity.className = "app-identity";

      const mark = document.createElement("span");
      mark.className = "app-mark";
      mark.setAttribute("aria-hidden", "true");
      mark.textContent = monogram(app.name);
      identity.append(mark);

      const copy = document.createElement("div");
      copy.className = "app-copy";

      const name = document.createElement("h3");
      name.className = "app-name";
      name.textContent = app.name;
      copy.append(name);

      const status = document.createElement("p");
      status.className = "app-state";
      status.dataset.state = app.running === null ? "unknown" : app.running ? "running" : "stopped";
      status.textContent = appStatusLabel(app);
      copy.append(status);

      identity.append(copy);
      row.append(identity);

      const actions = document.createElement("div");
      actions.className = "app-actions";

      const launch = createActionButton("Launch", "launch", app);
      const quit = createActionButton("Quit", "quit", app);
      actions.append(launch, quit);
      row.append(actions);

      appList.append(row);
    }
  }

  function createActionButton(label, action, app) {
    const button = document.createElement("button");
    button.className = `button button-${action}`;
    button.type = "button";
    button.dataset.action = action;
    button.dataset.appID = app.id;
    button.textContent = label;
    button.setAttribute("aria-label", `${label} ${app.name}`);

    const pending = state.pendingIDs.has(app.id);
    button.disabled = pending
      || (action === "launch" && app.running === true)
      || (action === "quit" && app.running === false);
    button.setAttribute("aria-busy", String(pending));

    button.addEventListener("click", () => runAction(app, action));
    return button;
  }

  async function loadApps() {
    if (state.catalogRequest) {
      return state.catalogRequest;
    }

    clearFeedback();
    setRefreshBusy(true);
    setConnection("connecting", "Loading catalog");
    appList.setAttribute("aria-busy", "true");

    state.catalogRequest = requestJSON("/apps")
      .then((payload) => {
        state.apps = parseApps(payload);
        renderApps();
        hideAuth();
        setConnection("connected", "Connected");
        lastUpdated.textContent = `Updated ${new Intl.DateTimeFormat(undefined, {
          hour: "numeric",
          minute: "2-digit",
        }).format(new Date())}`;
      })
      .catch((error) => {
        if (isUnauthorized(error)) {
          clearCatalogForAuthFailure();
          tokenInput.focus();
        }
        setConnection("error", "Unavailable");
        appList.setAttribute("aria-busy", "false");
        setFeedback(
          "error",
          "Could not load registered apps",
          isUnauthorized(error)
            ? "The token was rejected. Enter a new token and try again."
            : getErrorMessage(error, "The local API returned an error."),
          isUnauthorized(error) ? "Enter token" : "Retry",
          isUnauthorized(error)
            ? () => tokenInput.focus()
            : loadApps,
        );
      })
      .finally(() => {
        setRefreshBusy(false);
        state.catalogRequest = null;
      });

    return state.catalogRequest;
  }

  async function runAction(app, action) {
    if (state.pendingIDs.has(app.id)) {
      return;
    }

    state.pendingIDs.add(app.id);
    renderApps();
    clearFeedback();

    try {
      const encodedID = encodeURIComponent(app.id);
      const payload = await requestJSON(`/apps/${encodedID}/${action}`, { method: "POST" });
      const resultApp = payload && typeof payload.app === "object" ? normalizeApp(payload.app) : null;
      const index = state.apps.findIndex((candidate) => candidate.id === app.id);
      if (resultApp && index >= 0) {
        state.apps[index] = resultApp;
      } else if (index >= 0) {
        state.apps[index] = { ...state.apps[index], running: action === "launch" };
      }
      renderApps();
      setFeedback(
        "success",
        `${app.name} ${action === "launch" ? "launched" : "quit"}`,
        "The Mac accepted the request.",
      );
    } catch (error) {
      if (isUnauthorized(error)) {
        clearCatalogForAuthFailure();
        tokenInput.focus();
      }
      renderApps();
      setFeedback(
        "error",
        `Could not ${action} ${app.name}`,
        isUnauthorized(error)
          ? "The token was rejected. Enter a new token and try again."
          : getErrorMessage(error, "The local API returned an error."),
        "Retry",
        isUnauthorized(error) ? () => tokenInput.focus() : () => runAction(app, action),
      );
    } finally {
      state.pendingIDs.delete(app.id);
      renderApps();
    }
  }

  refreshButton.addEventListener("click", loadApps);
  authForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const token = tokenInput.value.trim();
    if (!token) {
      tokenInput.focus();
      return;
    }
    accessToken = token;
    loadApps();
  });

  showAuth();
})();
