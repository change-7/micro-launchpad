package com.pdg.galaxymicrolaunchpad

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccessTime
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AlternateEmail
import androidx.compose.material.icons.outlined.Android
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.Archive
import androidx.compose.material.icons.outlined.ArrowCircleDown
import androidx.compose.material.icons.outlined.ArrowCircleUp
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowLeft
import androidx.compose.material.icons.outlined.ArrowRight
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Article
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Autorenew
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Bookmark
import androidx.compose.material.icons.outlined.BuildCircle
import androidx.compose.material.icons.outlined.ChatBubble
import androidx.compose.material.icons.outlined.CheckCircleOutline
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.Event
import androidx.compose.material.icons.outlined.FiberManualRecord
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.FormatListBulleted
import androidx.compose.material.icons.outlined.FormatListNumbered
import androidx.compose.material.icons.outlined.Functions
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Headphones
import androidx.compose.material.icons.outlined.HelpOutline
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.Keyboard
import androidx.compose.material.icons.outlined.KeyboardCommandKey
import androidx.compose.material.icons.outlined.KeyboardControlKey
import androidx.compose.material.icons.outlined.KeyboardOptionKey
import androidx.compose.material.icons.outlined.Label
import androidx.compose.material.icons.outlined.LaptopMac
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material.icons.outlined.Mail
import androidx.compose.material.icons.outlined.Map
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.Message
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.NetworkCheck
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.Numbers
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PauseCircle
import androidx.compose.material.icons.outlined.Percent
import androidx.compose.material.icons.outlined.PersonOutline
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.Photo
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Print
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.QrCode
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.ShoppingCart
import androidx.compose.material.icons.outlined.ShowChart
import androidx.compose.material.icons.outlined.Shuffle
import androidx.compose.material.icons.outlined.SkipNext
import androidx.compose.material.icons.outlined.SkipPrevious
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.StopCircle
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.TabletMac
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material.icons.outlined.TravelExplore
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.Tv
import androidx.compose.material.icons.outlined.Undo
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.VolumeDown
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material.icons.outlined.VolumeUp
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material.icons.outlined.Whatshot
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.ui.graphics.vector.ImageVector
import java.util.Locale

/** Maps macOS SF Symbol identifiers to the closest bundled Material icon. */
internal fun iconForSymbol(symbol: String): ImageVector {
    return when (symbol.trim().lowercase(Locale.ROOT)) {
        // 실행 및 탐색
        "play.fill" -> Icons.Outlined.PlayArrow
        "pause.fill" -> Icons.Outlined.Pause
        "stop.fill" -> Icons.Outlined.Stop
        "forward.fill", "forward.end.fill" -> Icons.Outlined.SkipNext
        "backward.fill", "backward.end.fill" -> Icons.Outlined.SkipPrevious
        "play.circle.fill" -> Icons.Outlined.PlayCircle
        "pause.circle.fill" -> Icons.Outlined.PauseCircle
        "stop.circle.fill" -> Icons.Outlined.StopCircle
        "arrow.left", "chevron.left" -> Icons.Outlined.ArrowLeft
        "arrow.right", "chevron.right" -> Icons.Outlined.ArrowRight
        "arrow.up", "chevron.up" -> Icons.Outlined.ArrowUpward
        "arrow.down", "chevron.down" -> Icons.Outlined.ArrowDownward
        "arrow.clockwise" -> Icons.Outlined.Autorenew
        "arrow.counterclockwise", "arrow.uturn.backward" -> Icons.Outlined.Undo

        // 앱 및 기기
        "terminal", "terminal.fill" -> Icons.Outlined.Terminal
        "macwindow", "macwindow.on.rectangle", "display", "laptopcomputer" -> Icons.Outlined.LaptopMac
        "iphone" -> Icons.Outlined.PhoneAndroid
        "ipad" -> Icons.Outlined.TabletMac
        "applelogo" -> Icons.Outlined.LaptopMac
        "command" -> Icons.Outlined.KeyboardCommandKey
        "option" -> Icons.Outlined.KeyboardOptionKey
        "control" -> Icons.Outlined.KeyboardControlKey
        "power" -> Icons.Outlined.Stop
        "computermouse", "keyboard" -> Icons.Outlined.Keyboard
        "printer" -> Icons.Outlined.Print
        "externaldrive", "externaldrive.connected.to.line.below" -> Icons.Outlined.Storage
        "server.rack" -> Icons.Outlined.Dns
        "cpu" -> Icons.Outlined.Memory
        "wrench.and.screwdriver" -> Icons.Outlined.BuildCircle

        // 파일 및 생산성
        "globe", "globe.americas" -> Icons.Outlined.Public
        "safari" -> Icons.Outlined.TravelExplore
        "folder", "folder.fill" -> Icons.Outlined.FolderOpen
        "doc", "doc.text", "doc.richtext", "doc.plaintext" -> Icons.Outlined.Description
        "newspaper" -> Icons.Outlined.Article
        "archivebox" -> Icons.Outlined.Archive
        "tray", "tray.full" -> Icons.Outlined.Inbox
        "paperclip" -> Icons.Outlined.AttachFile
        "link" -> Icons.Outlined.Link
        "bookmark", "bookmark.fill" -> Icons.Outlined.Bookmark
        "tag", "tag.fill" -> Icons.Outlined.Label
        "calendar" -> Icons.Outlined.Event
        "clock" -> Icons.Outlined.AccessTime
        "checklist" -> Icons.Outlined.Checklist
        "list.bullet" -> Icons.Outlined.FormatListBulleted
        "list.number" -> Icons.Outlined.FormatListNumbered
        "pencil", "highlighter", "square.and.pencil", "note.text" -> Icons.Outlined.EditNote

        // 검색, 통신 및 공유
        "magnifyingglass", "scope" -> Icons.Outlined.Search
        "at" -> Icons.Outlined.AlternateEmail
        "envelope", "envelope.fill" -> Icons.Outlined.Mail
        "message", "message.fill" -> Icons.Outlined.Message
        "bubble.left", "bubble.left.and.bubble.right" -> Icons.Outlined.ChatBubble
        "phone", "phone.fill" -> Icons.Outlined.PhoneAndroid
        "video", "video.fill" -> Icons.Outlined.Videocam
        "person.fill", "person.crop.circle" -> Icons.Outlined.PersonOutline
        "person.2.fill" -> Icons.Outlined.Group
        "bell", "bell.fill" -> Icons.Outlined.NotificationsActive
        "qrcode" -> Icons.Outlined.QrCode
        "square.and.arrow.up" -> Icons.Outlined.IosShare
        "square.and.arrow.down" -> Icons.Outlined.FileDownload
        "arrow.down.circle" -> Icons.Outlined.ArrowCircleDown
        "arrow.up.circle" -> Icons.Outlined.ArrowCircleUp

        // 미디어
        "camera.viewfinder", "camera.fill" -> Icons.Outlined.PhotoCamera
        "doc.on.clipboard" -> Icons.Outlined.ContentPaste
        "music.note" -> Icons.Outlined.MusicNote
        "speaker.wave.2", "speaker.wave.3" -> Icons.Outlined.VolumeUp
        "speaker.wave.1" -> Icons.Outlined.VolumeDown
        "speaker.slash" -> Icons.Outlined.VolumeOff
        "moon", "moon.stars" -> Icons.Outlined.DarkMode
        "photo", "photo.fill", "photo.on.rectangle" -> Icons.Outlined.Photo
        "film", "play.rectangle.fill" -> Icons.Outlined.Movie
        "tv" -> Icons.Outlined.Tv
        "headphones" -> Icons.Outlined.Headphones
        "mic", "mic.fill" -> Icons.Outlined.Mic
        "gamecontroller", "rectangle.on.rectangle" -> Icons.Outlined.Devices
        "record.circle" -> Icons.Outlined.FiberManualRecord
        "shuffle" -> Icons.Outlined.Shuffle
        "repeat" -> Icons.Outlined.Repeat

        // 웹, 네트워크 및 클라우드
        "wifi", "wifi.exclamationmark" -> Icons.Outlined.Wifi
        "antenna.radiowaves.left.and.right", "network" -> Icons.Outlined.NetworkCheck
        "cloud", "cloud.fill" -> Icons.Outlined.Cloud
        "cloud.upload", "icloud.and.arrow.up" -> Icons.Outlined.CloudUpload
        "cloud.download", "icloud.and.arrow.down" -> Icons.Outlined.CloudDownload
        "bolt.horizontal.circle", "bolt", "bolt.fill" -> Icons.Outlined.Bolt
        "lock.shield", "lock.fill" -> Icons.Outlined.Lock
        "key", "key.fill", "lock.open" -> Icons.Outlined.LockOpen
        "eye" -> Icons.Outlined.Visibility
        "eye.slash" -> Icons.Outlined.VisibilityOff

        // 시스템 및 상태
        "gearshape", "gear" -> Icons.Outlined.Settings
        "slider.horizontal.3" -> Icons.Outlined.Tune
        "ellipsis", "ellipsis.circle" -> Icons.Outlined.MoreHoriz
        "plus" -> Icons.Outlined.Add
        "minus" -> Icons.Outlined.Remove
        "xmark", "xmark.circle", "xmark.circle.fill" -> Icons.Outlined.RemoveCircleOutline
        "checkmark", "checkmark.circle", "checkmark.circle.fill" -> Icons.Outlined.CheckCircleOutline
        "questionmark", "questionmark.circle" -> Icons.Outlined.HelpOutline
        "info.circle" -> Icons.Outlined.Info
        "exclamationmark.triangle", "exclamationmark.circle" -> Icons.Outlined.WarningAmber
        "wand.and.stars", "sparkles" -> Icons.Outlined.AutoAwesome
        "flame" -> Icons.Outlined.Whatshot
        "sun.max", "cloud.sun" -> Icons.Outlined.WbSunny
        "house", "house.fill" -> Icons.Outlined.Home
        "heart", "heart.fill", "star", "star.fill" -> Icons.Outlined.Star
        "flag", "flag.fill" -> Icons.Outlined.Flag
        "pin", "pin.fill" -> Icons.Outlined.PushPin
        "location", "location.fill", "mappin" -> Icons.Outlined.LocationOn
        "map" -> Icons.Outlined.Map
        "cart" -> Icons.Outlined.ShoppingCart
        "creditcard" -> Icons.Outlined.CreditCard

        // 숫자 및 개발 도구
        "1.circle.fill", "2.circle.fill", "3.circle.fill", "4.circle.fill", "5.circle.fill",
        "6.circle.fill", "7.circle.fill", "8.circle.fill", "9.circle.fill", "10.circle.fill",
        "number" -> Icons.Outlined.Numbers
        "percent" -> Icons.Outlined.Percent
        "chevron.left.forwardslash.chevron.right", "curlybraces" -> Icons.Outlined.Code
        "function", "sum" -> Icons.Outlined.Functions
        "hammer", "shippingbox" -> Icons.Outlined.Inventory2
        "chart.bar" -> Icons.Outlined.BarChart
        "chart.line.uptrend.xyaxis" -> Icons.Outlined.ShowChart
        "gauge.with.dots.needle.67percent", "speedometer" -> Icons.Outlined.Speed
        "square.grid.2x2" -> Icons.Outlined.Apps
        else -> Icons.Outlined.MoreHoriz
    }
}

internal fun isIconlessSymbol(symbol: String): Boolean = symbol.trim().isEmpty()
