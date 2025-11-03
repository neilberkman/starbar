import Cocoa
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.xuku.starbar", category: "notificationmanager")

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
  private(set) var badgeCount = 0
  weak var statusItem: NSStatusItem?

  override init() {
    super.init()
    // Use osascript for notifications since UNUserNotificationCenter requires proper app bundle
    // UNUserNotificationCenter.current().delegate = self
    // requestPermission()
  }

  func requestPermission() {
    // Not needed for osascript notifications
    // UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
    //   if let error = error {
    //     logger.error("❌ Notification permission error: \(error)")
    //   } else if granted {
    //     logger.info("✓ Notification permissions granted")
    //   } else {
    //     logger.warning("⚠️ Notification permissions denied")
    //   }
    // }
  }

  func showStarNotification(repo: String, user: String) {
    // Use osascript for notifications since UserNotifications requires proper app bundle
    let script = """
      display notification "\(repo) from @\(user)" with title "⭐ New Star" sound name "default"
      """

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]

    do {
      try task.run()
      logger.info("✓ Notification sent via osascript")
    } catch {
      logger.error("❌ Failed to show notification: \(error)")
    }

    incrementBadge()
  }

  func incrementBadge() {
    badgeCount += 1
    updateBadge()
  }

  func decrementBadge() {
    if badgeCount > 0 {
      badgeCount -= 1
      updateBadge()
    }
  }

  func clearBadge() {
    badgeCount = 0
    updateBadge()
  }

  private func updateBadge() {
    DispatchQueue.main.async { [weak self] in
      guard let button = self?.statusItem?.button else { return }

      if self?.badgeCount ?? 0 > 0 {
        button.image = self?.createBadgedIcon(count: self?.badgeCount ?? 0)
      } else {
        button.image = NSImage(systemSymbolName: "star", accessibilityDescription: "StarBar")
      }
    }
  }

  func createBadgedIcon(count: Int) -> NSImage {
    let baseImage = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "StarBar")!
    let size = NSSize(width: 22, height: 22)

    let image = NSImage(size: size)
    image.lockFocus()

    // Draw star
    baseImage.draw(in: NSRect(origin: .zero, size: size))

    // Draw badge
    if count > 0 {
      let badgeSize: CGFloat = 14
      let badgeOffset: CGFloat = 1
      let badge = NSRect(
        x: size.width - badgeSize + badgeOffset,
        y: size.height - badgeSize + badgeOffset,
        width: badgeSize,
        height: badgeSize
      )

      NSColor.systemRed.setFill()
      let path = NSBezierPath(ovalIn: badge)
      path.fill()

      let text = count > 99 ? "99+" : "\(count)"
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 9),
        .foregroundColor: NSColor.white,
      ]
      let textSize = text.size(withAttributes: attrs)
      let textRect = NSRect(
        x: badge.midX - textSize.width / 2,
        y: badge.midY - textSize.height / 2 + 0.5,
        width: textSize.width,
        height: textSize.height
      )
      text.draw(in: textRect, withAttributes: attrs)
    }

    image.unlockFocus()
    return image
  }

  // Handle notification clicks
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let repo = response.notification.request.content.userInfo["repo"] as? String {
      let url = URL(string: "https://github.com/\(repo)")!
      NSWorkspace.shared.open(url)
    }
    completionHandler()
  }
}
