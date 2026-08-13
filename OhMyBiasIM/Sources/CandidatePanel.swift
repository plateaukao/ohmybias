import Cocoa
import QuartzCore

/// Custom candidate panel replacing buggy IMKCandidates.
/// Supports two modes:
///   - "cursor": vertical list near cursor (original)
///   - "fixed": horizontal bar above Dock, semi-transparent, draggable, right-click menu
final class CandidatePanel: NSPanel {
    static let shared = CandidatePanel()

    // MARK: - Font & attribute caches

    private static var fontCache: [CGFloat: NSFont] = [:]
    private static var monoFontCache: [CGFloat: NSFont] = [:]

    private static let hcShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = .black.withAlphaComponent(0.6)
        s.shadowBlurRadius = 2
        s.shadowOffset = NSSize(width: 0, height: -1)
        return s
    }()

    private static func cachedFont(size: CGFloat) -> NSFont {
        if let f = fontCache[size] { return f }
        let f = NSFont.systemFont(ofSize: size)
        fontCache[size] = f
        return f
    }

    private static func cachedMonoFont(size: CGFloat) -> NSFont {
        if let f = monoFontCache[size] { return f }
        let f = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        monoFontCache[size] = f
        return f
    }

    private static let fullWidthDigitMap: [Character: String] = [
        "0": "０", "1": "１", "2": "２", "3": "３", "4": "４",
        "5": "５", "6": "６", "7": "７", "8": "８", "9": "９"
    ]

    private var cachedFixedFont: NSFont?
    private var cachedHC: Bool?
    private var cachedNormalAttrs: [NSAttributedString.Key: Any]?
    private var cachedHighlightAttrs: [NSAttributedString.Key: Any]?

    private var lastA11yNotify: TimeInterval = 0

    // MARK: - Shared state

    private var candidates: [String] = []
    private var selKeys: [Character] = []
    private var highlightIndex = 0
    private var userNavigated = false
    private let pageSize = 9
    private var showGeneration = 0
    var onCandidateSelected: ((String) -> Void)?

    // MARK: - Cursor-mode views

    private let stackView = NSStackView()
    private var labels: [NSTextField] = []
    private var pageIndicator: NSTextField!

    private var stackConstraints: [NSLayoutConstraint] = []

    // MARK: - Fixed-mode views

    private let fixedLabel = NSTextField(labelWithString: "")
    private var dragOffset: NSPoint = .zero
    private var isDraggingPanel = false
    private var mouseDownOnCandidate = false
    private var composingText = ""
    var targetScreen: NSScreen?
    var modeTag: String = ""  // 當前模式標籤（非 "繁中" 時顯示）

    private var isFixed: Bool { OhMyBiasPrefs.panelPosition == "fixed" }
    private var effectiveScreen: NSScreen { targetScreen ?? NSScreen.main ?? NSScreen.screens[0] }

    // MARK: - Init

    private init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        self.level = .popUpMenu
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let contentVisual = NSVisualEffectView()
        contentVisual.material = .popover
        contentVisual.state = .active
        contentVisual.wantsLayer = true
        contentVisual.layer?.cornerRadius = 6
        self.contentView = contentVisual

        // --- Cursor-mode setup (original) ---
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 1
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        contentVisual.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackConstraints = [
            stackView.topAnchor.constraint(equalTo: contentVisual.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentVisual.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentVisual.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentVisual.bottomAnchor),
        ]
        NSLayoutConstraint.activate(stackConstraints)


        for _ in 0..<pageSize {
            let label = NSTextField(labelWithString: "")
            label.font = Self.cachedMonoFont(size: OhMyBiasPrefs.fontSize)
            label.isBordered = false
            label.isEditable = false
            label.wantsLayer = true
            label.layer?.cornerRadius = 3
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            stackView.addArrangedSubview(label)
            labels.append(label)
        }

        pageIndicator = NSTextField(labelWithString: "")
        pageIndicator.font = Self.cachedFont(size: 11)
        pageIndicator.isBordered = false
        pageIndicator.isEditable = false
        pageIndicator.isHidden = true
        stackView.addArrangedSubview(pageIndicator)

        // --- Fixed-mode setup ---
        fixedLabel.font = Self.cachedFont(size: OhMyBiasPrefs.fixedFontSize)
        fixedLabel.textColor = .labelColor
        fixedLabel.alignment = .center
        fixedLabel.isBordered = false
        fixedLabel.isEditable = false
        fixedLabel.translatesAutoresizingMaskIntoConstraints = false
        fixedLabel.isHidden = true
        contentVisual.addSubview(fixedLabel)
        NSLayoutConstraint.activate([
            fixedLabel.leadingAnchor.constraint(equalTo: contentVisual.leadingAnchor, constant: 12),
            fixedLabel.trailingAnchor.constraint(equalTo: contentVisual.trailingAnchor, constant: -12),
            fixedLabel.centerYAnchor.constraint(equalTo: contentVisual.centerYAnchor),
        ])

        // Hover cursor for fixed mode
        let tracking = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        contentVisual.addTrackingArea(tracking)

        // Screen change observer
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        setupAccessibility()
    }

    // MARK: - Accessibility

    private func setupAccessibility() {
        // 視窗層級
        self.setAccessibilityLabel("選字窗")
        self.setAccessibilityRole(.window)
        self.setAccessibilityHelp("使用數字鍵 1-9 選擇候選字，空白鍵送出目前字詞")

        // 堆疊視圖（游標模式）
        stackView.setAccessibilityLabel("候選字列表")
        stackView.setAccessibilityRole(.list)

        // 固定模式標籤
        fixedLabel.setAccessibilityLabel("候選字列")
        fixedLabel.setAccessibilityRole(.staticText)
    }

    private func throttledA11yNotify() {
        let now = CACurrentMediaTime()
        guard now - lastA11yNotify >= 0.016 else { return }
        lastA11yNotify = now
        NSAccessibility.post(element: self, notification: .valueChanged)
        // Announce current highlighted candidate for VoiceOver
        if highlightIndex < candidates.count {
            let idx = highlightIndex - pageStart + 1
            let text = "第\(idx)，\(candidates[highlightIndex])"
            NSAccessibility.post(element: self,
                                 notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    private var useReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    @objc private func screenParametersChanged() {
        if isFixed && isVisible { repositionFixed() }
    }

    // MARK: - Thread safety

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    // MARK: - Public API

    /// When true, cursor mode falls back to fixed-mode display (incompatible apps)
    var fallbackFixed = false

    func show(candidates: [String], selKeys: [Character], at origin: NSPoint, composing: String = "") {
        onMain {
            guard !candidates.isEmpty else { self.hide(); return }
            self.showGeneration += 1
            self.candidates = candidates
            self.selKeys = selKeys
            self.highlightIndex = 0
            self.userNavigated = false
            self.composingText = composing

            if self.isFixed || self.fallbackFixed {
                self.showFixed()
            } else {
                self.showCursor(at: origin)
            }
        }
    }

    /// Show a one-line guide message in the fixed-mode panel
    func showGuide(_ message: String) {
        onMain {
            self.showGeneration += 1
            self.candidates = []
            self.switchToFixedLayout()
            self.fixedLabel.stringValue = message
            self.fixedLabel.font = Self.cachedFont(size: 14)
            self.fixedLabel.textColor = .secondaryLabelColor
            self.fixedLabel.sizeToFit()
            self.repositionFixed()
            self.alphaValue = 0.9
            self.orderFront(nil)
        }
    }

    func hide() {
        onMain {
            let gen = self.showGeneration
            if (self.isFixed || self.fallbackFixed) && self.isVisible {
                if self.useReducedMotion {
                    self.alphaValue = 0
                    self.orderOut(nil)
                } else {
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = 0.12
                        self.animator().alphaValue = 0
                    }, completionHandler: {
                        // 只有在沒被重新 show 的情況下才關閉
                        guard self.showGeneration == gen else { return }
                        self.orderOut(nil)
                    })
                }
            } else {
                self.orderOut(nil)
            }
            self.candidates = []
            self.composingText = ""
        }
    }

    func selectByKey(_ c: Character) -> String? {
        guard let idx = selKeys.firstIndex(of: c) else { return nil }
        let i = selKeys.distance(from: selKeys.startIndex, to: idx)
        let actual = pageStart + i
        guard actual < candidates.count else { return nil }
        return candidates[actual]
    }

    func pageDown() {
        onMain {
            let newStart = self.pageStart + self.pageSize
            if newStart < self.candidates.count {
                self.highlightIndex = newStart
                self.rebuildCurrentMode()
            }
        }
    }

    func pageUp() {
        onMain {
            self.highlightIndex = max(0, self.pageStart - self.pageSize)
            self.rebuildCurrentMode()
        }
    }

    func moveUp() {
        onMain {
            if self.highlightIndex > 0 { self.highlightIndex -= 1; self.userNavigated = true; self.rebuildCurrentMode() }
        }
    }

    func moveDown() {
        onMain {
            if self.highlightIndex < self.candidates.count - 1 { self.highlightIndex += 1; self.userNavigated = true; self.rebuildCurrentMode() }
        }
    }

    /// Navigate prev/next — works for both vertical (up/down) and horizontal (left/right)
    func movePrev() { moveUp() }
    func moveNext() { moveDown() }

    var isFixedMode: Bool { isFixed || fallbackFixed }

    func selectedCandidate() -> String? {
        guard highlightIndex < candidates.count else { return nil }
        return candidates[highlightIndex]
    }

    var isVisible_: Bool { isVisible }

    private var pageStart: Int { (highlightIndex / pageSize) * pageSize }

    /// 只有 1–2 個候選時精簡顯示：不加數字前綴、不高亮
    /// （方向鍵導覽後恢復高亮，否則 Enter 確認的焦點不可見）
    private var isCompact: Bool { candidates.count <= 2 }
    private var showsHighlight: Bool { !isCompact || userNavigated }

    private func keyLabel(_ c: Character) -> String {
        Self.fullWidthDigitMap[c] ?? String(c)
    }

    private func rebuildCurrentMode() {
        if isFixed || fallbackFixed { rebuildFixedLabel() } else { rebuildLabels() }
    }

    // MARK: - Cursor mode (vertical or horizontal layout)

    private var cursorIsHorizontal: Bool { OhMyBiasPrefs.cursorHorizontal }

    private func showCursor(at origin: NSPoint) {
        switchToCursorLayout()
        rebuildLabels()
        positionWindow(at: origin)
        orderFront(nil)
    }

    private func switchToCursorLayout() {
        stackView.isHidden = false
        fixedLabel.isHidden = true
        // Update orientation based on preference
        stackView.orientation = cursorIsHorizontal ? .horizontal : .vertical
        stackView.alignment = cursorIsHorizontal ? .centerY : .leading
        stackView.spacing = cursorIsHorizontal ? 4 : 1
        NSLayoutConstraint.activate(stackConstraints)
        alphaValue = 1.0
        (contentView as? NSVisualEffectView)?.material = .popover
        (contentView as? NSVisualEffectView)?.layer?.cornerRadius = 6
    }

    private func rebuildLabels() {
        let fontSize = OhMyBiasPrefs.fontSize
        let hc = OhMyBiasPrefs.highContrast
        let start = pageStart
        let end = min(start + pageSize, candidates.count)
        let horizontal = cursorIsHorizontal

        for i in 0..<pageSize {
            let label = labels[i]
            label.font = hc
                ? NSFont.boldSystemFont(ofSize: fontSize)
                : Self.cachedMonoFont(size: fontSize)
            label.shadow = hc ? Self.hcShadow : nil
            if start + i < end {
                let candIdx = start + i
                let keyChar = i < selKeys.count ? keyLabel(selKeys[i]) : " "
                label.stringValue = isCompact ? candidates[candIdx] : "\(keyChar)\(candidates[candIdx])"
                label.setAccessibilityLabel("第\(i + 1)，\(candidates[candIdx])")
                label.isHidden = false
                if candIdx == highlightIndex && showsHighlight {
                    label.drawsBackground = true
                    label.backgroundColor = NSColor.selectedContentBackgroundColor
                    label.textColor = .selectedMenuItemTextColor
                } else {
                    label.drawsBackground = false
                    label.backgroundColor = .clear
                    label.textColor = .labelColor
                }
                // Horizontal mode: add horizontal padding to each label
                if horizontal {
                    label.setContentHuggingPriority(.required, for: .horizontal)
                } else {
                    label.setContentHuggingPriority(.defaultLow, for: .horizontal)
                }
            } else {
                label.isHidden = true
            }
        }

        let totalPages = (candidates.count + pageSize - 1) / pageSize
        if totalPages > 1 {
            let currentPage = pageStart / pageSize + 1
            pageIndicator.stringValue = horizontal ? "◀\(currentPage)/\(totalPages)▶" : "  \(currentPage)/\(totalPages)"
            pageIndicator.textColor = .secondaryLabelColor
            pageIndicator.isHidden = false
        } else {
            pageIndicator.isHidden = true
        }

        layoutIfNeeded()
        let size = stackView.fittingSize
        if horizontal {
            let screen = effectiveScreen
            let maxW = screen.frame.width * 0.8
            setContentSize(NSSize(width: min(size.width + 16, maxW), height: max(size.height, 28)))
        } else {
            let maxW: CGFloat = 360
            setContentSize(NSSize(width: min(max(size.width + 12, 80), maxW), height: size.height))
        }
        throttledA11yNotify()

        if let elem = contentView as? NSVisualEffectView {
            NSAccessibility.post(element: elem, notification: .valueChanged)
        }
    }

    private func positionWindow(at origin: NSPoint) {
        let screen = effectiveScreen
        var pt = origin
        pt.y -= (self.frame.height + 4)
        // 底部溢出：翻到游標上方
        if pt.y < screen.visibleFrame.minY { pt.y = origin.y + 20 }
        // 右邊界
        if pt.x + frame.width > screen.visibleFrame.maxX {
            pt.x = screen.visibleFrame.maxX - frame.width
        }
        // 左邊界
        if pt.x < screen.visibleFrame.minX {
            pt.x = screen.visibleFrame.minX
        }
        setFrameOrigin(pt)
    }

    // MARK: - Fixed mode (horizontal bar above Dock)

    private func showFixed() {
        let wasVisible = isVisible
        switchToFixedLayout()
        rebuildFixedLabel()
        repositionFixed()
        if !wasVisible {
            if useReducedMotion {
                alphaValue = OhMyBiasPrefs.fixedAlpha
                orderFront(nil)
            } else {
                alphaValue = 0
                orderFront(nil)
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.12
                    self.animator().alphaValue = OhMyBiasPrefs.fixedAlpha
                })
            }
        } else {
            // 取消進行中的淡出動畫，確保 alpha 正確
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            animator().alphaValue = OhMyBiasPrefs.fixedAlpha
            NSAnimationContext.endGrouping()
            orderFront(nil)
        }
    }

    private func switchToFixedLayout() {
        NSLayoutConstraint.deactivate(stackConstraints)
        stackView.isHidden = true
        fixedLabel.isHidden = false
        (contentView as? NSVisualEffectView)?.material = .hudWindow
        (contentView as? NSVisualEffectView)?.layer?.cornerRadius = 8
    }

    private func rebuildFixedLabel() {
        let start = pageStart
        let end = min(start + pageSize, candidates.count)
        let sep = "  "
        let fontSize = OhMyBiasPrefs.fixedFontSize
        let font = Self.cachedFont(size: fontSize)
        fixedLabel.font = font

        if cachedFixedFont !== font || cachedHC != OhMyBiasPrefs.highContrast {
            cachedFixedFont = font
            let hc = OhMyBiasPrefs.highContrast
            cachedHC = hc
            let boldFont = hc ? NSFont.boldSystemFont(ofSize: fontSize) : font
            var normal: [NSAttributedString.Key: Any] = [.font: boldFont, .foregroundColor: NSColor.labelColor]
            if hc { normal[.shadow] = Self.hcShadow }
            cachedNormalAttrs = normal
            cachedHighlightAttrs = [
                .font: boldFont,
                .foregroundColor: NSColor.selectedMenuItemTextColor,
                .backgroundColor: NSColor.selectedContentBackgroundColor,
            ]
        }
        let normalAttrs = cachedNormalAttrs!
        let highlightAttrs = cachedHighlightAttrs!

        let result = NSMutableAttributedString()

        if !composingText.isEmpty {
            result.append(NSAttributedString(string: "[\(composingText)]" + sep, attributes: normalAttrs))
        }

        for i in start..<end {
            if i > start { result.append(NSAttributedString(string: sep, attributes: normalAttrs)) }
            let keyIdx = i - start
            let keyChar = keyIdx < selKeys.count ? keyLabel(selKeys[keyIdx]) : " "
            let text = isCompact ? candidates[i] : "\(keyChar)\(candidates[i])"
            let attrs = (i == highlightIndex && showsHighlight) ? highlightAttrs : normalAttrs
            result.append(NSAttributedString(string: text, attributes: attrs))
        }

        let totalPages = (candidates.count + pageSize - 1) / pageSize
        if totalPages > 1 {
            let currentPage = pageStart / pageSize + 1
            result.append(NSAttributedString(string: sep + "◀ \(currentPage)/\(totalPages) ▶", attributes: normalAttrs))
        }

        if !modeTag.isEmpty && modeTag != "繁中" {
            let tagFont = Self.cachedFont(size: OhMyBiasPrefs.fixedFontSize * 0.65)
            let tagAttrs: [NSAttributedString.Key: Any] = [
                .font: tagFont, .foregroundColor: NSColor.secondaryLabelColor
            ]
            result.append(NSAttributedString(string: sep + "[\(modeTag)]", attributes: tagAttrs))
        }

        fixedLabel.attributedStringValue = result

        let size = fixedLabel.intrinsicContentSize
        let h = size.height + 8
        let screen = effectiveScreen
        let maxW = screen.frame.width * 0.85
        setContentSize(NSSize(width: min(size.width + 24, maxW), height: h))
        throttledA11yNotify()
    }

    private func repositionFixed() {
        let screen = effectiveScreen
        let dockH = dockBottomHeight(screen: screen)
        var y = screen.frame.minY + dockH + OhMyBiasPrefs.fixedYOffset

        var x: CGFloat
        switch OhMyBiasPrefs.fixedAlignment {
        case "left":   x = screen.frame.minX + 16
        case "right":  x = screen.frame.maxX - frame.width - 16
        case "custom": x = screen.frame.minX + OhMyBiasPrefs.fixedXOffset
        default:       x = screen.frame.midX - frame.width / 2
        }
        // 寬度隨候選數變動、螢幕解析度也可能改變 — 位置一律夾回螢幕內
        x = max(screen.frame.minX, min(x, screen.frame.maxX - frame.width))
        y = max(screen.frame.minY, min(y, screen.frame.maxY - frame.height))
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func dockBottomHeight(screen: NSScreen) -> CGFloat {
        let diff = screen.visibleFrame.minY - screen.frame.minY
        return max(diff, 0)
    }

    // MARK: - Fixed mode: hover cursor

    override func mouseEntered(with event: NSEvent) {
        if isFixed { NSCursor.openHand.push() }
    }

    override func mouseExited(with event: NSEvent) {
        if isFixed { NSCursor.pop() }
    }

    // MARK: - Fixed mode: dragging (any direction; click = select, drag = move)

    override func mouseDown(with event: NSEvent) {
        if isFixed {
            // 選字延到 mouseUp 才判定，讓文字區也能直接拖曳
            let loc = event.locationInWindow
            mouseDownOnCandidate = fixedLabel.hitTest(contentView!.convert(loc, to: fixedLabel)) is NSTextField
            dragOffset = loc
            isDraggingPanel = false
        } else {
            // Cursor mode: check which label was clicked
            let loc = event.locationInWindow
            let viewLoc = contentView!.convert(loc, to: stackView)
            for i in 0..<pageSize {
                let label = labels[i]
                guard !label.isHidden else { continue }
                if label.frame.contains(viewLoc) {
                    let candIdx = pageStart + i
                    guard candIdx < candidates.count else { break }
                    label.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.5).cgColor
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        label.layer?.backgroundColor = nil
                    }
                    highlightIndex = candIdx
                    rebuildCurrentMode()
                    onCandidateSelected?(candidates[candIdx])
                    return
                }
            }
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isFixed else { super.mouseDragged(with: event); return }
        let loc = event.locationInWindow
        if !isDraggingPanel {
            // 3pt 門檻：手抖不算拖曳，保留點擊選字
            guard abs(loc.x - dragOffset.x) > 3 || abs(loc.y - dragOffset.y) > 3 else { return }
            isDraggingPanel = true
            NSCursor.closedHand.push()
        }
        let screen = effectiveScreen
        let newX = frame.origin.x + (loc.x - dragOffset.x)
        let newY = frame.origin.y + (loc.y - dragOffset.y)
        let clampedX = max(screen.frame.minX, min(newX, screen.frame.maxX - frame.width))
        let clampedY = max(screen.frame.minY, min(newY, screen.frame.maxY - frame.height))
        setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    override func mouseUp(with event: NSEvent) {
        guard isFixed else { super.mouseUp(with: event); return }
        if isDraggingPanel {
            isDraggingPanel = false
            NSCursor.pop()
            // 記住拖曳後位置：Y 存 Dock 上方偏移、X 存螢幕左緣偏移
            let screen = effectiveScreen
            OhMyBiasPrefs.fixedYOffset = frame.origin.y - screen.frame.minY - dockBottomHeight(screen: screen)
            OhMyBiasPrefs.fixedXOffset = frame.origin.x - screen.frame.minX
            OhMyBiasPrefs.fixedAlignment = "custom"
        } else if mouseDownOnCandidate {
            selectClickedCandidate()
        }
        mouseDownOnCandidate = false
    }

    /// 固定模式點擊文字區＝送出第一個候選（單一 label 無法定位個別候選）
    private func selectClickedCandidate() {
        let start = pageStart
        for i in 0..<pageSize {
            let candIdx = start + i
            guard candIdx < candidates.count else { break }
            if i < selKeys.count, let c = selectByKey(selKeys[i]) {
                onCandidateSelected?(c)
                return
            }
        }
    }

    // MARK: - Fixed mode: right-click context menu

    override func rightMouseDown(with event: NSEvent) {
        guard isFixed else { super.rightMouseDown(with: event); return }

        let menu = NSMenu()

        // Alignment
        for (title, key) in [("靠左", "left"), ("置中", "center"), ("靠右", "right")] {
            let item = NSMenuItem(title: title, action: #selector(menuSetAlignment(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            if OhMyBiasPrefs.fixedAlignment == key { item.state = .on }
            menu.addItem(item)
        }
        if OhMyBiasPrefs.fixedAlignment == "custom" {
            let item = NSMenuItem(title: "自訂（已拖曳）", action: nil, keyEquivalent: "")
            item.state = .on
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // Transparency submenu
        let alphaMenu = NSMenu()
        for pct in stride(from: 100, through: 30, by: -10) {
            let item = NSMenuItem(title: "\(pct)%", action: #selector(menuSetAlpha(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = CGFloat(pct) / 100.0
            if abs(OhMyBiasPrefs.fixedAlpha - CGFloat(pct) / 100.0) < 0.05 { item.state = .on }
            alphaMenu.addItem(item)
        }
        let alphaItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        alphaItem.submenu = alphaMenu
        menu.addItem(alphaItem)

        menu.addItem(.separator())

        // Font size submenu
        let fontMenu = NSMenu()
        for size in stride(from: 14, through: 48, by: 2) {
            let item = NSMenuItem(title: "\(size)pt", action: #selector(menuSetFontSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = CGFloat(size)
            if abs(OhMyBiasPrefs.fixedFontSize - CGFloat(size)) < 1 { item.state = .on }
            fontMenu.addItem(item)
        }
        let fontItem = NSMenuItem(title: "字體大小", action: nil, keyEquivalent: "")
        fontItem.submenu = fontMenu
        menu.addItem(fontItem)

        menu.addItem(.separator())

        // Mode toggle
        let toggleTitle = isFixed ? "切換到游標跟隨" : "切換到固定位置"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(menuToggleMode), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        NSMenu.popUpContextMenu(menu, with: event, for: contentView!)
    }

    @objc private func menuSetAlignment(_ sender: NSMenuItem) {
        OhMyBiasPrefs.fixedAlignment = sender.representedObject as! String
        repositionFixed()
    }

    @objc private func menuSetAlpha(_ sender: NSMenuItem) {
        let a = sender.representedObject as! CGFloat
        OhMyBiasPrefs.fixedAlpha = a
        alphaValue = a
    }

    @objc private func menuSetFontSize(_ sender: NSMenuItem) {
        OhMyBiasPrefs.fixedFontSize = sender.representedObject as! CGFloat
        rebuildFixedLabel()
        repositionFixed()
    }

    @objc private func menuToggleMode() {
        OhMyBiasPrefs.panelPosition = isFixed ? "cursor" : "fixed"
        hide()
    }
}
