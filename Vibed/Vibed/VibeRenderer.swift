// Vibed/VibeRenderer.swift

import SwiftUI
import WebKit
import CoreMotion
import CoreHaptics

// MARK: - VibeRenderer

struct VibeRenderer: UIViewRepresentable {
    let vibe: Vibe

    /// When false, no two-finger navigation gesture is added and multi-touch
    /// is not blocked in JS — so the Vibe itself owns all touch input.
    var enableNavigationGesture: Bool = true

    /// Called once when a two-finger drag begins.
    var onDragBegan: () -> Void = { }
    /// Called continuously during a two-finger drag with the cumulative X/Y translation.
    var onDragChanged: (CGPoint) -> Void = { _ in }
    /// Called when a two-finger drag ends, with the X/Y velocity.
    var onDragEnded: (CGPoint) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let config = WKWebViewConfiguration()

        // ── Media ────────────────────────────────────────────────────────────
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true

        // ── JS bridge ────────────────────────────────────────────────────────
        config.userContentController.addUserScript(
            WKUserScript(source: makeBridgeJS(blockMultiTouch: enableNavigationGesture),
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true)
        )
        let proxy = WeakScriptMessageHandler(coordinator: context.coordinator)
        config.userContentController.add(proxy, name: "haptics")

        // ── WKWebView ────────────────────────────────────────────────────────
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.scrollView.showsVerticalScrollIndicator = false
        wv.scrollView.showsHorizontalScrollIndicator = false
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black

        // ── Container: parent of WKWebView ───────────────────────────────────
        let container = UIView()
        container.backgroundColor = .black
        container.addSubview(wv)
        wv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // ── Two-finger navigation gesture on the CONTAINER ───────────────────
        if enableNavigationGesture {
            let pan = UIPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.cancelsTouchesInView = true
            pan.delegate = context.coordinator
            container.addGestureRecognizer(pan)
        }

        context.coordinator.onDragBegan   = onDragBegan
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded   = onDragEnded
        context.coordinator.attach(to: wv)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        context.coordinator.onDragBegan   = onDragBegan
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded   = onDragEnded

        guard context.coordinator.loadedVibeID != vibe.id else { return }
        context.coordinator.loadedVibeID = vibe.id
        context.coordinator.webView?.loadHTMLString(vibe.htmlContent, baseURL: nil)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.tearDown()
        coordinator.webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: "haptics")
    }
}

// MARK: - Coordinator

final class Coordinator: NSObject,
                         WKNavigationDelegate,
                         WKUIDelegate,
                         VibeHapticsHandler,
                         UIGestureRecognizerDelegate {

    var loadedVibeID: UUID?
    private(set) weak var webView: WKWebView?

    var onDragBegan:   () -> Void        = { }
    var onDragChanged: (CGPoint) -> Void = { _ in }
    var onDragEnded:   (CGPoint) -> Void = { _ in }

    private let motion = CMMotionManager()

    func attach(to wv: WKWebView) {
        webView = wv
        startMotion()
    }

    // MARK: Two-finger pan

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            onDragBegan()
            let t = recognizer.translation(in: recognizer.view)
            onDragChanged(CGPoint(x: t.x, y: t.y))
        case .changed:
            let t = recognizer.translation(in: recognizer.view)
            onDragChanged(CGPoint(x: t.x, y: t.y))
        case .ended, .cancelled, .failed:
            let v = recognizer.velocity(in: recognizer.view)
            onDragEnded(CGPoint(x: v.x, y: v.y))
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf other: UIGestureRecognizer
    ) -> Bool { false }

    // MARK: Motion bridge

    func startMotion() {
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 60.0
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
                guard let data, let wv = self?.webView else { return }
                let G = 9.81
                let ax = (data.userAcceleration.x + data.gravity.x) * G
                let ay = (data.userAcceleration.y + data.gravity.y) * G
                let az = (data.userAcceleration.z + data.gravity.z) * G
                let ux = data.userAcceleration.x * G
                let uy = data.userAcceleration.y * G
                let uz = data.userAcceleration.z * G
                let toDeg = 180.0 / Double.pi
                let ra = data.rotationRate.x * toDeg
                let rb = data.rotationRate.y * toDeg
                let rg = data.rotationRate.z * toDeg
                let alpha = (data.attitude.yaw   * toDeg + 360).truncatingRemainder(dividingBy: 360)
                let beta  =  data.attitude.pitch * toDeg
                let gamma =  data.attitude.roll  * toDeg
                guard ax.isFinite, ay.isFinite, az.isFinite else { return }
                let js = """
                (function(){
                  window.dispatchEvent(new CustomEvent('_nativeMotion',{detail:{
                    ax:\(ax),ay:\(ay),az:\(az),
                    ux:\(ux),uy:\(uy),uz:\(uz),
                    ra:\(ra),rb:\(rb),rg:\(rg)
                  }}));
                  window.dispatchEvent(new CustomEvent('_nativeOrientation',{detail:{
                    alpha:\(alpha),beta:\(beta),gamma:\(gamma)
                  }}));
                })();
                """
                wv.evaluateJavaScript(js, completionHandler: nil)
            }
        } else if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 1.0 / 60.0
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let data, let wv = self?.webView else { return }
                let G = 9.81
                let ax = data.acceleration.x * G
                let ay = data.acceleration.y * G
                let az = data.acceleration.z * G
                guard ax.isFinite else { return }
                let js = """
                window.dispatchEvent(new CustomEvent('_nativeMotion',{detail:{
                  ax:\(ax),ay:\(ay),az:\(az),
                  ux:0,uy:0,uz:0,ra:0,rb:0,rg:0
                }}));
                """
                wv.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    // MARK: Haptics

    func handleHapticMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        switch type {
        case "impact":
            let style: UIImpactFeedbackGenerator.FeedbackStyle
            switch body["style"] as? String {
            case "light":  style = .light
            case "heavy":  style = .heavy
            case "rigid":  style = .rigid
            case "soft":   style = .soft
            default:       style = .medium
            }
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        case "notification":
            let kind: UINotificationFeedbackGenerator.FeedbackType
            switch body["notificationType"] as? String {
            case "warning": kind = .warning
            case "error":   kind = .error
            default:        kind = .success
            }
            UINotificationFeedbackGenerator().notificationOccurred(kind)
        case "selection":
            UISelectionFeedbackGenerator().selectionChanged()
        case "vibrate":
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        default: break
        }
    }

    // MARK: Teardown

    func tearDown() {
        if motion.isDeviceMotionActive  { motion.stopDeviceMotionUpdates() }
        if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        decisionHandler(scheme == "http" || scheme == "https" ? .cancel : .allow)
    }

    // MARK: WKUIDelegate — camera & microphone

    @available(iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }
}

// MARK: - WeakScriptMessageHandler

protocol VibeHapticsHandler: AnyObject {
    func handleHapticMessage(_ body: [String: Any])
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var coordinator: VibeHapticsHandler?
    init(coordinator: VibeHapticsHandler) { self.coordinator = coordinator }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        DispatchQueue.main.async { [weak self] in
            self?.coordinator?.handleHapticMessage(body)
        }
    }
}

// MARK: - JS Bridge

private func makeBridgeJS(blockMultiTouch: Bool) -> String {
    let blockSection = blockMultiTouch ? """

  // ── Two-finger touch block ─────────────────────────────────────────────────
  // Feed navigation owns all two-finger gestures. Block them in the capture
  // phase before any Vibe script sees them.
  var _blockMulti = function (e) {
    if (e.touches.length > 1) { e.stopPropagation(); e.preventDefault(); }
  };
  document.addEventListener('touchstart', _blockMulti, { capture: true, passive: false });
  document.addEventListener('touchmove',  _blockMulti, { capture: true, passive: false });

""" : "\n"

    return """
(function () {
  'use strict';
\(blockSection)  // ── Motion / orientation event bridge ─────────────────────────────────────
  var _motionListeners = [];
  var _orientListeners = [];
  var _origAdd    = window.addEventListener.bind(window);
  var _origRemove = window.removeEventListener.bind(window);

  window.addEventListener = function (type, fn, opts) {
    if (type === 'devicemotion')      { _motionListeners.push(fn); return; }
    if (type === 'deviceorientation') { _orientListeners.push(fn); return; }
    _origAdd(type, fn, opts);
  };
  window.removeEventListener = function (type, fn, opts) {
    if (type === 'devicemotion') {
      _motionListeners = _motionListeners.filter(function (l) { return l !== fn; });
      return;
    }
    if (type === 'deviceorientation') {
      _orientListeners = _orientListeners.filter(function (l) { return l !== fn; });
      return;
    }
    _origRemove(type, fn, opts);
  };

  _origAdd('_nativeMotion', function (e) {
    var d = e.detail;
    var fake = {
      acceleration:                 { x: d.ux, y: d.uy, z: d.uz },
      accelerationIncludingGravity: { x: d.ax, y: d.ay, z: d.az },
      rotationRate:                 { alpha: d.ra, beta: d.rb, gamma: d.rg },
      interval: 1 / 60
    };
    for (var i = 0; i < _motionListeners.length; i++) {
      try { _motionListeners[i](fake); } catch (_) {}
    }
  });

  _origAdd('_nativeOrientation', function (e) {
    var d = e.detail;
    var fake = { alpha: d.alpha, beta: d.beta, gamma: d.gamma, absolute: false };
    for (var i = 0; i < _orientListeners.length; i++) {
      try { _orientListeners[i](fake); } catch (_) {}
    }
  });

  function _granted() { return Promise.resolve('granted'); }
  if (typeof DeviceMotionEvent      !== 'undefined' && typeof DeviceMotionEvent.requestPermission      === 'function') DeviceMotionEvent.requestPermission      = _granted;
  if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') DeviceOrientationEvent.requestPermission = _granted;

  // ── Haptics bridge ────────────────────────────────────────────────────────
  function _haptic(msg) {
    try { window.webkit.messageHandlers.haptics.postMessage(msg); } catch (_) {}
  }

  if (!navigator.vibrate) {
    navigator.vibrate = function (pattern) {
      _haptic({ type: 'vibrate', pattern: Array.isArray(pattern) ? pattern : [pattern] });
      return true;
    };
  }

  Object.defineProperty(window, 'Haptics', {
    value: Object.freeze({
      impact:       function (style) { _haptic({ type: 'impact',       style: style || 'medium' }); },
      notification: function (type)  { _haptic({ type: 'notification', notificationType: type || 'success' }); },
      selection:    function ()      { _haptic({ type: 'selection' }); }
    }),
    writable: false
  });

})();
"""
}
