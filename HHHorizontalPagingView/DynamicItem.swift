//
//  DynamicItem.swift
//  Demo
//
//  Created by Zhang Yuanming on 4/6/17.
//  Copyright © 2017 weijingyun. All rights reserved.
//

import UIKit

class DynamicItem: NSObject, UIDynamicItem {
    var center: CGPoint = CGPoint.zero

    var bounds: CGRect = CGRect.zero

    var transform: CGAffineTransform = CGAffineTransform.identity

    override init() {
        super.init()
        self.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
    }
}
