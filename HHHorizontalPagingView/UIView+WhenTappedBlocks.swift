//
//  UIView+WhenTappedBlocks.swift
//  Demo
//
//  Created by Zhang Yuanming on 4/5/17.
//  Copyright © 2017 weijingyun. All rights reserved.
//

import UIKit


extension UIView: UIGestureRecognizerDelegate {
    typealias JMWhenTappedBlock = () -> Void

    fileprivate struct AssociatedKey {
        static var kWhenTappedBlockKey = "kWhenTappedBlockKey"
        static var kWhenDoubleTappedBlockKey = "kWhenDoubleTappedBlockKey"
        static var kWhenTwoFingerTappedBlockKey = "kWhenTwoFingerTappedBlockKey"
        static var kWhenTouchedDownBlockKey = "kWhenTouchedDownBlockKey"
        static var kWhenTouchedUpBlockKey = "kWhenTouchedUpBlockKey"
    }

    func block() -> JMWhenTappedBlock? {
        return objc_getAssociatedObject(self, &AssociatedKey.kWhenTappedBlockKey) as? JMWhenTappedBlock
    }

    func runBlockForKey(_ blockKey: String) {
        let block: JMWhenTappedBlock? = objc_getAssociatedObject(self, blockKey) as? JMWhenTappedBlock
        if let block = block {
            block()
        }
    }

    func setBlock(_ block: JMWhenTappedBlock, forKey blockKey: String) {
        self.isUserInteractionEnabled = true
        objc_setAssociatedObject(self, blockKey, block, .OBJC_ASSOCIATION_COPY_NONATOMIC);
    }

    func whenTapped(_ block: JMWhenTappedBlock) {
        let gesture = self.addTapGestureRecognizerWithTaps(1, touches: 1, selector: #selector(viewWasTapped))
        self.addRequiredToDoubleTapsRecognizer(gesture)
        self.setBlock(block, forKey: AssociatedKey.kWhenTappedBlockKey)
    }

    func whenDoubleTapped(_ block: JMWhenTappedBlock) {
        let gesture = self.addTapGestureRecognizerWithTaps(2, touches: 1, selector: #selector(viewWasDoubleTapped))
        self.addRequiredToDoubleTapsRecognizer(gesture)
        self.setBlock(block, forKey: AssociatedKey.kWhenDoubleTappedBlockKey)
    }

    func whenTwoFingerTapped(_ block: JMWhenTappedBlock) {
        self.addTapGestureRecognizerWithTaps(1, touches: 2, selector: #selector(viewWasTwoFingerTapped))

        self.setBlock(block, forKey: AssociatedKey.kWhenTwoFingerTappedBlockKey)
    }

    func whenTouchedDown(_ block: JMWhenTappedBlock) {
        self.setBlock(block, forKey: AssociatedKey.kWhenTouchedDownBlockKey)
    }

    func whenTouchedUp(_ block: JMWhenTappedBlock) {
        self.setBlock(block, forKey: AssociatedKey.kWhenTouchedUpBlockKey)
    }


    // MARK: -

    @discardableResult
    func addTapGestureRecognizerWithTaps(_ taps: Int, touches: Int, selector: Selector) -> UITapGestureRecognizer {

        let tapGesture = UITapGestureRecognizer(target: self, action: selector)
        tapGesture.delegate = self
        tapGesture.numberOfTapsRequired = taps
        tapGesture.numberOfTouchesRequired = touches
        self.addGestureRecognizer(tapGesture)

        return tapGesture;
    }

    func addRequirementToSingleTapsRecognizer(_ recognizer: UIGestureRecognizer) {
        for gesture in gestureRecognizers ?? [] {
            if gesture is UITapGestureRecognizer {
                let tapGesture = gesture as! UITapGestureRecognizer
                if tapGesture.numberOfTouchesRequired == 1 &&
                    tapGesture.numberOfTapsRequired == 1 {
                    tapGesture.require(toFail: recognizer)
                }
            }
        }
    }

    func addRequiredToDoubleTapsRecognizer(_ recognizer: UIGestureRecognizer) {
        for gesture in gestureRecognizers ?? [] {
            if gesture is UITapGestureRecognizer {
                let tapGesture = gesture as! UITapGestureRecognizer
                if tapGesture.numberOfTouchesRequired == 2 &&
                    tapGesture.numberOfTapsRequired == 1 {
                    tapGesture.require(toFail: recognizer)
                }
            }
        }
    }


    // MARK: -Callbacks

    func viewWasTapped() {
        runBlockForKey(AssociatedKey.kWhenTappedBlockKey)
    }

    func viewWasDoubleTapped() {
        runBlockForKey(AssociatedKey.kWhenTappedBlockKey)
    }

    func viewWasTwoFingerTapped() {
        runBlockForKey(AssociatedKey.kWhenTappedBlockKey)
    }

    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        runBlockForKey(AssociatedKey.kWhenTouchedDownBlockKey)
    }

    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        runBlockForKey(AssociatedKey.kWhenTouchedUpBlockKey)
    }

    // MARK: 模拟响应者链条 由被触发的View 向它的兄弟控件 父控件 延伸查找响应
    func viewWasTappedPoint(_ point: CGPoint) {
        clickOnThePoint(point)
    }

    @discardableResult
    func clickOnThePoint(_ point: CGPoint) -> Bool {
        if let superView = superview, superView is UIWindow {
            return false
        }

        if let block = self.block() {
            block()
            return true
        }

        var click = false

        if let subviews = superview?.subviews {
            for subView in subviews {
                let objPoint = subView.convert(point, from: self)
                if !subView.frame.contains(objPoint) {
                    continue
                }
                if let block = self.block() {
                    block()
                    click = true
                    break
                }
            }
        }

        if !click {
            return superview?.clickOnThePoint(point) ?? false
        }

        return click

    }

}

