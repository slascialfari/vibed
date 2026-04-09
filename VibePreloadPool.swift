// Vibed/VibePreloadPool.swift

import SwiftUI
import Combine
import UIKit
import WebKit
import CoreMotion

// MARK: - VibePreloadPool

/// Owns a sliding window of WKWebViews centred on the current index.
/// Always keeps current ±2 preloaded; evicts anything outside that window.
/// One CMMotionManager broadcasts sensor data to all live webviews.
@MainActor
final class VibePreloadPool: ObservableObject {

    private struct Slot {
        let webView: WKWebView
        let nav: SlotNav   // strong ref — webView holds only weak refs to delegates
        let msg: SlotMsg
    }

    private var slots: [Int: Slot] = [:]
    private let motion = CMMotionManager()

    // MARK: - Public API

    func webView(at index: Int) -> WKWebView? { slots[index]?.webView }

    /// Load real HTML for current ±2 slots so adjacent cards are already rendered
    /// before the user swipes to them. New slots fade in after didFinish.
    func prime(around center: Int, vibes: [Vibe]) {
        guard !vibes.isEmpty else { return }
        let lo   = max(0, center - 2)
        let hi   = min(vibes.count - 1, center + 2)
        let keep = lo...hi

        for key in slots.keys where !keep.contains(key) { evict(key) }
        for i in keep where slots[i] == nil { loadHTML(i, vibe: vibes[i]) }

        ensureMotion()
    }

    /// Called when navigating away from a slot. Silently reloads the HTML
    /// off-screen so the vibe is fresh and ready for the next visit.
    func resetSlot(index: Int, vibe: Vibe) {
        guard let wv = slots[index]?.webView else { return }
        wv.alpha = 0
        wv.loadHTMLString(vibe.htmlContent, baseURL: nil)
    }

    // MARK: - Private

    private func loadHTML(_ index: Int, vibe: Vibe) {
        let slot = makeSlot()
        slots[index] = slot
        slot.webView.loadHTMLString(vibe.htmlContent, baseURL: nil)
    }

    private func makeSlot() -> Slot {
        let msg = SlotMsg()

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.userContentController.addUserScript(
            WKUserScript(source: poolBridgeJS,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true)
        )
        config.userContentController.add(msg, name: "haptics")

        // Use the screen bounds so HTML/JS reads the correct viewport size
        // (window.innerWidth, canvas size, etc.) while the WKWebView is off-screen.
        let wv = WKWebView(frame: UIScreen.main.bounds, configuration: config)
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.scrollView.showsVerticalScrollIndicator = false
        wv.scrollView.showsHorizontalScrollIndicator = false
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.alpha = 0   // invisible until didFinish fires

        let nav = SlotNav()
        wv.navigationDelegate = nav
        wv.uiDelegate = nav

        return Slot(webView: wv, nav: nav, msg: msg)
    }

    private func evict(_ index: Int) {
        guard let slot = slots.removeValue(forKey: index) else { return }
        slot.webView.stopLoading()
        slot.webView.navigationDelegate = nil
        slot.webView.uiDelegate = nil
        slot.webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "haptics")
    }

    private func ensureMotion() {
        guard !motion.isDeviceMotionActive, motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
            guard let data, let self else { return }
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
            let alpha = (data.attitude.yaw * toDeg + 360).truncatingRemainder(dividingBy: 360)
            let beta  =  data.attitude.pitch * toDeg
            let gamma =  data.attitude.roll  * toDeg
            guard ax.isFinite, ay.isFinite, az.isFinite else { return }
            let js = """
            (function(){
              window.dispatchEvent(new CustomEvent('_nativeMotion',{detail:{
                ax:\(ax),ay:\(ay),az:\(az),ux:\(ux),uy:\(uy),uz:\(uz),
                ra:\(ra),rb:\(rb),rg:\(rg)}}));
              window.dispatchEvent(new CustomEvent('_nativeOrientation',{detail:{
                alpha:\(alpha),beta:\(beta),gamma:\(gamma)}}));
            })();
            """
            for slot in self.slots.values {
                slot.webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }
}

// MARK: - SlotNav

private final class SlotNav: NSObject, WKNavigationDelegate, WKUIDelegate {

    func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) {
        UIView.animate(withDuration: 0.2) { wv.alpha = 1 }
    }

    func webView(_ wv: WKWebView,
                 decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = action.request.url?.scheme?.lowercased()
        decisionHandler(scheme == "http" || scheme == "https" ? .cancel : .allow)
    }

    func webView(_ wv: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }
}

// MARK: - SlotMsg (haptics)

private final class SlotMsg: NSObject, WKScriptMessageHandler {
    func userContentController(_ c: WKUserContentController, didReceive msg: WKScriptMessage) {
        guard let body = msg.body as? [String: Any],
              let type = body["type"] as? String else { return }
        switch type {
        case "impact":
            let s: UIImpactFeedbackGenerator.FeedbackStyle
            switch body["style"] as? String {
            case "light": s = .light
            case "heavy": s = .heavy
            case "rigid": s = .rigid
            case "soft":  s = .soft
            default:      s = .medium
            }
            UIImpactFeedbackGenerator(style: s).impactOccurred()
        case "notification":
            let k: UINotificationFeedbackGenerator.FeedbackType
            switch body["notificationType"] as? String {
            case "warning": k = .warning
            case "error":   k = .error
            default:        k = .success
            }
            UINotificationFeedbackGenerator().notificationOccurred(k)
        case "selection":
            UISelectionFeedbackGenerator().selectionChanged()
        default:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

// MARK: - VibeCardView
//
// Thin UIViewRepresentable that hosts a pool-provided WKWebView.
// It never creates its own WKWebView; it just places the one it receives
// into a black UIView container. Swapping to a new WKWebView (on index
// change) is handled in updateUIView.

struct VibeCardView: UIViewRepresentable {
    let webView: WKWebView?
    let isInteractive: Bool

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.isUserInteractionEnabled = isInteractive
        if let wv = webView { attach(wv, to: container) }
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        container.isUserInteractionEnabled = isInteractive
        let current = container.subviews.first as? WKWebView
        guard current !== webView else { return }
        if let old = current {
            // Deactivate constraints before removing to avoid unsatisfiable warnings
            NSLayoutConstraint.deactivate(old.constraints)
            old.removeFromSuperview()
        }
        if let wv = webView { attach(wv, to: container) }
    }

    private func attach(_ wv: WKWebView, to container: UIView) {
        // addSubview auto-removes from any previous superview.
        // Use constraints so the WKWebView fills the container regardless of
        // when makeUIView is called (container.bounds may be .zero at that point).
        wv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        // Fire a JS resize event so content that read window.innerWidth at load
        // time can re-layout to the real container size.
        wv.evaluateJavaScript("window.dispatchEvent(new Event('resize'));",
                              completionHandler: nil)
    }
}

// MARK: - Bridge JS (mirrors VibeRenderer bridgeJS)

private let poolBridgeJS = """
(function () {
  'use strict';

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
