import Cocoa
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
  private(set) var badgeCount = 0
  weak var statusItem: NSStatusItem?

  override init() {
    super.init()
    UNUserNotificationCenter.current().delegate = self
    requestPermission()
  }

  func requestPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error = error {
        NSLog("❌ Notification permission error: \(error)")
      } else if granted {
        NSLog("✓ Notification permissions granted")
      } else {
        NSLog("⚠️ Notification permissions denied")
      }
    }
  }

  func showStarNotification(repo: String, user: String) {
    let content = UNMutableNotificationContent()
    content.title = "⭐ New Star"
    content.body = "\(repo) from @\(user)"
    content.sound = .default
    content.userInfo = ["repo": repo]

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        NSLog("❌ Failed to show notification: \(error)")
      } else {
        NSLog("✓ Notification delivered successfully")
      }
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
