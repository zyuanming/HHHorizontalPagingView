//
//  UIScrollView+Dragging.swift
//  Demo
//
//  Created by Zhang Yuanming on 4/5/17.
//  Copyright © 2017 weijingyun. All rights reserved.
//

import UIKit

public extension DispatchQueue {

    private static var _onceTracker = [String]()

    /**
     Executes a block of code, associated with a unique token, only once.  The code is thread safe and will
     only execute the code once even in the presence of multithreaded calls.

     - parameter token: A unique reverse DNS style name such as com.vectorform.<name> or a GUID
     - parameter block: Block to execute once
     */
    public class func once(token: String, block:() -> Void) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }

        if _onceTracker.contains(token) {
            return
        }

        _onceTracker.append(token)
        block()
    }
}


extension UIScrollView {

    override open static func initialize() {
        let performActivitySel = NSSelectorFromString("isDragging")
        DispatchQueue.once(token: "UIScrollView") {
            let swizzledSelector = NSSelectorFromString("swizzled_isDragging")

            let originalMethod = class_getInstanceMethod(self, performActivitySel)
            let swizzledMethod = class_getInstanceMethod(self, swizzledSelector)

            let didAddMethod = class_addMethod(self, performActivitySel, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))

            if didAddMethod {
                class_replaceMethod(self, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
            } else {
                method_exchangeImplementations(originalMethod, swizzledMethod);
            }
        }
    }

    fileprivate struct AssociatedKey {
        static var hhh_isRefresh = 1
        static var hhh_startRefresh = 2
        static var isDragging = 3
    }

    var hhh_isRefresh: Bool {
        set {
            objc_setAssociatedObject(self, &AssociatedKey.hhh_isRefresh, newValue, .OBJC_ASSOCIATION_ASSIGN)
        }
        get {
            return objc_getAssociatedObject(self, &AssociatedKey.hhh_isRefresh) as? Bool ?? false
        }
    }

    var hhh_startRefresh: Bool {
        set {
            objc_setAssociatedObject(self, &AssociatedKey.hhh_startRefresh, newValue, .OBJC_ASSOCIATION_ASSIGN)
        }
        get {
            return objc_getAssociatedObject(self, &AssociatedKey.hhh_startRefresh) as? Bool ?? false
        }
    }

    func swizzled_isDragging() -> Bool {
        let dragging = objc_getAssociatedObject(self, #function) as? Bool ?? false
        return dragging || swizzled_isDragging()
    }

    func setDragging(_ dragging: Bool) {
        objc_setAssociatedObject(self, &AssociatedKey.isDragging, NSNumber(value: isDragging), .OBJC_ASSOCIATION_RETAIN)
    }

}
