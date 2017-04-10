//
//  HHHorizontalPagingView.swift
//  Demo
//
//  Created by Zhang Yuanming on 4/6/17.
//  Copyright © 2017 weijingyun. All rights reserved.
//

import UIKit

let kHHHorizontalScrollViewRefreshStartNotification = "kHHHorizontalScrollViewRefreshStartNotification"
let kHHHorizontalScrollViewRefreshEndNotification = "kHHHorizontalScrollViewRefreshEndNotification"
let kHHHorizontalTakeBackRefreshEndNotification = "kHHHorizontalTakeBackRefreshEndNotification"

@objc protocol HHHorizontalPagingViewDelegate: NSObjectProtocol {

    // 下方左右滑UIScrollView设置
    func numberOfSectionsInPagingView(_ pagingView: HHHorizontalPagingView) -> Int
    func pagingView(_ pagingView: HHHorizontalPagingView, viewAtIndex: Int) -> UIScrollView


    //headerView 设置
    func headerHeightInPagingView(_ pagingView: HHHorizontalPagingView) -> CGFloat
    func headerViewInPagingView(_ pagingView: HHHorizontalPagingView) -> UIView

    //segmentButtons
    func segmentHeightInPagingView(_ pagingView: HHHorizontalPagingView) -> CGFloat
    func segmentButtonsInPagingView(_ pagingView: HHHorizontalPagingView) -> [UIButton]

    // 非当前页点击segment
    @objc optional func pagingView(_ pagingView: HHHorizontalPagingView,
                                   segmentDidSelected item: UIButton,
                                   atIndex selectedIndex: Int)
    // 当前页点击segment
    @objc optional func pagingView(_ pagingView: HHHorizontalPagingView,
                                   segmentDidSelectedSameItem item: UIButton,
                                   atIndex selectedIndex: Int)

    // 视图切换完成时调用 从哪里切换到哪里
    @objc optional func pagingView(_ pagingView: HHHorizontalPagingView, didSwitchIndex aIndex: Int, to toIndex: Int)

    /*
     与 magnifyTopConstraint 属性相对应  下拉时如需要放大，则传入的图片的上边距约束
     考虑到开发中很少使用原生约束，故放开代理方法 用于用户自行根据 偏移处理相应效果

     该版本将 magnifyTopConstraint 属性删除
     该代理 和 监听 self.contentOffset 效果是一样的
     */
    @objc optional func pagingView(_ pagingView: HHHorizontalPagingView, scrollTopOffset offset: CGFloat)
}

class HHHorizontalPagingView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var delegate: HHHorizontalPagingViewDelegate
    var isSwitching: Bool = false
    var contentViewArray: [UIScrollView] = []
    var headerViewHeight: CGFloat = 0
    var segmentBarHeight: CGFloat = 0
    var segmentTopSpace: CGFloat = 0
    var currentScrollView: UIScrollView?
    var headerView: UIView?
    var horizontalCollectionView: UICollectionView
    var headerOriginYConstraint: NSLayoutConstraint?
    var headerSizeHeightConstraint: NSLayoutConstraint?
    var segmentButtons: [UIButton] = []
    var segmentButtonConstraintArray: [NSLayoutConstraint] = []
    var currenPage: Int = 0
    var _pullOffset: CGFloat = 0
    var currenSelectedBut: Int = 0
    var maxCacheCout: Int = 3
    var isGesturesSimulate: Bool = false
    var isDragging: Bool = false
    var isScroll: Bool = false
    var allowPullToRefresh: Bool = false
    var currentTouchButton: UIButton?
    var currentTouchView: UIView?
    var currentTouchViewPoint: CGPoint?
    var segmentButtonSize: CGSize = CGSize.zero {
        didSet {
            configureSegmentButtonLayout()
        }
    }
    /**
     *  用于模拟scrollView滚动
     */
    lazy var animator: UIDynamicAnimator = UIDynamicAnimator()
    var inertialBehavior: UIDynamicItemBehavior?
    lazy var segmentView: UIView = {
        let view = UIView()
        self.configureSegmentButtonLayout()
        return view
    }()

    let pagingCellIdentifier: String = "pagingCellIdentifier"
    let pagingScrollViewTag: Int = 2000
    let pagingButtonTag: Int = 1000

    fileprivate struct ContextKey {
        static var HHHorizontalPagingViewScrollContext = 1
        static var HHHorizontalPagingViewInsetContext = 2
        static var HHHorizontalPagingViewPanContext = 3
    }

    init(frame: CGRect, delegate: HHHorizontalPagingViewDelegate) {
        self.delegate = delegate

        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.scrollDirection = .horizontal

        horizontalCollectionView = UICollectionView(frame: frame, collectionViewLayout: layout)

        super.init(frame: frame)

        let section = delegate.numberOfSectionsInPagingView(self)
        self.registCellForm(0, to: section)

        self.horizontalCollectionView.backgroundColor                = UIColor.clear
        self.horizontalCollectionView.dataSource                     = self
        self.horizontalCollectionView.delegate                       = self
        self.horizontalCollectionView.isPagingEnabled                = true
        self.horizontalCollectionView.showsHorizontalScrollIndicator = false
        self.horizontalCollectionView.scrollsToTop                   = false

        // iOS10 上将该属性设置为 NO，就会预取cell了
        if #available(iOS 10.0, *) {
            horizontalCollectionView.isPrefetchingEnabled = false
        }

        let tempLayout: UICollectionViewFlowLayout = layout
        tempLayout.itemSize = horizontalCollectionView.frame.size
        addSubview(horizontalCollectionView)
        configureHeaderView()
        configureSegmentView()
        NotificationCenter.default.addObserver(self, selector: #selector(releaseCache), name: .UIApplicationDidReceiveMemoryWarning, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStart(_:)), name: NSNotification.Name(rawValue: kHHHorizontalScrollViewRefreshStartNotification), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshEnd(_:)), name: Notification.Name(rawValue:  kHHHorizontalScrollViewRefreshEndNotification), object: nil)

    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for scrollView in contentViewArray {
            removeObserverFor(scrollView)
        }

        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - UICollectionViewDataSource, UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return delegate.numberOfSectionsInPagingView(self)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        isSwitching = true
        let key = cellReuseIdentifierForIndex(indexPath.row)
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: key, for: indexPath)
        let v = scrollViewAtIndex(indexPath.row)

        if cell.contentView.tag != v.tag {
            cell.backgroundColor = UIColor.clear
            cell.contentView.subviews.forEach({_ in removeFromSuperview()})
            cell.tag = v.tag

            if let vc = viewControllerForView(v) {
                cell.contentView.addSubview(vc.view)

                vc.view.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addConstraints([
                    NSLayoutConstraint(item: vc.view, attribute: .top, relatedBy: .equal, toItem: cell.contentView, attribute: .top, multiplier: 1.0, constant: 0.0),
                    NSLayoutConstraint(item: vc.view, attribute: .bottom, relatedBy: .equal, toItem: cell.contentView, attribute: .bottom, multiplier: 1.0, constant: 0.0),
                    NSLayoutConstraint(item: vc.view, attribute: .left, relatedBy: .equal, toItem: cell.contentView, attribute: .left, multiplier: 1.0, constant: 0.0),
                    NSLayoutConstraint(item: vc.view, attribute: .right, relatedBy: .equal, toItem: cell.contentView, attribute: .right, multiplier: 1.0, constant: 0.0)
                ])
            }
            cell.layoutIfNeeded()
        }

        currentScrollView = v
        adjustOffsetContentView(v)
        return cell

    }


    // MARK: - Notification

    func releaseCache() {
        if let currentCount = currentScrollView?.tag {
            for scrollView in contentViewArray {
                if labs(scrollView.tag - currentCount) > 1 {
                    removeScrollView(scrollView)
                }
            }
        }
    }

    func refreshStart(_ notification: Notification) {
        if let obj = notification.object as? UIScrollView {
            for scrollView in contentViewArray {
                if scrollView == obj {
                    scrollView.hhh_startRefresh = true
                    scrollView.hhh_isRefresh = true
                    break
                }
            }
        }
    }

    func refreshEnd(_ notification: Notification) {
        if let obj = notification.object as? UIScrollView {
            for scrollView in contentViewArray {
                if scrollView == obj {
                    scrollView.hhh_startRefresh = false
                    scrollView.hhh_isRefresh = false
                    scrollView.setDragging(false)
                    break
                }
            }
        }
    }


    // MARK: - Gesture


    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {

        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let point = pan.translation(in: headerView)
            if fabs(point.y) <= fabs(point.x) {
                return false
            }
        }

        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func pan(_ pan: UIPanGestureRecognizer) {
        // 如果处于刷新中，作用在headerView上的手势不响应
        if currentScrollView?.hhh_isRefresh == true {
            return
        }

        // 手势模拟 兼容整体下来刷新
        isDragging = !(pan.state == .ended || pan.state == .failed)
        currentScrollView?.setDragging(self.isDragging)

        // 偏移计算
        let point = pan.translation(in: headerView)
        let contentOffset = currentScrollView!.contentOffset
        let border = -headerViewHeight - delegate.segmentHeightInPagingView(self)
        let offsety = contentOffset.y - point.y * (1/contentOffset.y * border * 0.8)
        currentScrollView?.contentOffset = CGPoint(x: contentOffset.x, y: offsety)

        if (pan.state == .ended || pan.state == .failed) {
            if contentOffset.y <= border {
                // 如果处于刷新
                if currentScrollView?.hhh_isRefresh == true {
                    return
                }
                // 模拟弹回效果
                UIView.animate(withDuration: 0.35, animations: { 
                    self.currentScrollView?.contentOffset = CGPoint(x: contentOffset.x, y: border)
                    self.layoutIfNeeded()
                })

            } else {
                // 模拟减速滚动效果

                let velocity = pan.velocity(in: headerView).y
                deceleratingAnimator(velocity)
            }
        }

        // 清零防止偏移累计

        pan.setTranslation(CGPoint.zero, in: headerView)
    }

    func deceleratingAnimator(_ velocity: CGFloat) {
        if let inertialBehavior = self.inertialBehavior {
            animator.removeBehavior(inertialBehavior)
        }

        let item = DynamicItem()
        item.center = CGPoint(x: 0, y: 0)

        // velocity是在手势结束的时候获取的竖直方向的手势速度
        let inertialBehavior = UIDynamicItemBehavior(items: [item])
        inertialBehavior.addLinearVelocity(CGPoint(x: 0, y: velocity * 0.025), for: item)

        // 通过尝试取2.0比较像系统的效果
        inertialBehavior.resistance = 2

        let maxOffset = currentScrollView!.contentSize.height - currentScrollView!.bounds.height
        inertialBehavior.action = { [weak self] in
            guard let strongSelf = self else { return }
            let contentOffset = strongSelf.currentScrollView!.contentOffset
            let speed = strongSelf.inertialBehavior!.linearVelocity(for: item).y
            var offset = contentOffset.y - speed

            if speed >= -0.2 {
                strongSelf.animator.removeBehavior(strongSelf.inertialBehavior!)
                strongSelf.inertialBehavior = nil

            } else if offset >= maxOffset {
                strongSelf.animator.removeBehavior(strongSelf.inertialBehavior!)
                strongSelf.inertialBehavior = nil
                offset = maxOffset

                // 模拟减速滚动到scrollView最底部时，先拉一点再弹回的效果
                UIView.animate(withDuration: 0.2, animations: { 
                    strongSelf.currentScrollView?.contentOffset = CGPoint(x: contentOffset.x, y: offset - speed)
                    strongSelf.layoutIfNeeded()
                }, completion: { (_) in
                    UIView.animate(withDuration: 0.25, animations: { 
                        strongSelf.currentScrollView?.contentOffset = CGPoint(x: contentOffset.x, y: offset)
                    })
                })
            } else {
                strongSelf.currentScrollView?.contentOffset = CGPoint(x: contentOffset.x, y: offset)
            }
        }

        self.inertialBehavior = inertialBehavior
        animator.addBehavior(inertialBehavior)
    }



    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        isScroll = true

        let offsetpage = scrollView.contentOffset.x / UIScreen.main.bounds.width
        let int_offsetPage = Int(offsetpage)
        let py = fabs(CGFloat(int_offsetPage) - offsetpage)
        if py <= 0.3 || py >= 0.7 {
            return
        }

        let currentPage = currenSelectedBut
        if offsetpage - CGFloat(currentPage) > 0 {
            if py > 0.55 {
                setSelectedButPage(currentPage + 1)
            }
        } else {
            if py < 0.45 {
                setSelectedButPage(currentPage - 1)
            }
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // 是否左右滚动  防止上下滚动的触发
        if !isScroll {
            return
        }

        isScroll = false
        let currentPage = scrollView.contentOffset.x / UIScreen.main.bounds.width
        didSwitchIndex(Int(currentPage), to: Int(currentPage))
    }


    // MARK: - Observer

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

        if context == &ContextKey.HHHorizontalPagingViewPanContext{
            isDragging = true
            horizontalCollectionView.isScrollEnabled = true
            if let stateInt = change?[NSKeyValueChangeKey.newKey] as? Int,
                let state = UIGestureRecognizerState(rawValue: stateInt) {
                if state == UIGestureRecognizerState.failed {
                    if let currentTouchButton = currentTouchButton {
                        segmentButtonEvent(currentTouchButton)
                    } else if let currentTouchView = currentTouchView {
                        currentTouchView.viewWasTappedPoint(currentTouchViewPoint!)
                    }
                    currentTouchView = nil
                    currentTouchButton = nil
                } else if state == .cancelled || state == .ended {
                    isDragging = false
                }
            }
        } else if context == &ContextKey.HHHorizontalPagingViewScrollContext {
            currentTouchView = nil
            currentTouchButton = nil
            if isSwitching {
                return
            }

            // 触发如果不是当前 ScrollView 不予响应
            if let object = object as? UIScrollView, object != currentScrollView {
                return
            }

            if let change = change {
                let oldOffsetY = (change[.oldKey] as? CGPoint)?.y ?? 0
                let newOffsetY = (change[.newKey] as? CGPoint)?.y ?? 0
                let deltaY = newOffsetY - oldOffsetY

                let headerViewHeight = self.headerViewHeight
                let headerDisplayHeight = headerViewHeight + (headerOriginYConstraint?.constant ?? 0)

                var py: CGFloat = 0

                if deltaY >= 0 {    //向上滚动
                    if headerDisplayHeight - deltaY <= self.segmentTopSpace {
                        py = -headerViewHeight + self.segmentTopSpace
                    } else {
                        py = (self.headerOriginYConstraint?.constant ?? 0) - deltaY
                    }
                    if headerDisplayHeight <= self.segmentTopSpace {
                        py = -headerViewHeight + self.segmentTopSpace
                    }
        
                    if !self.allowPullToRefresh {
                        self.headerOriginYConstraint?.constant = py
        
                    } else if (py < 0 && !self.currentScrollView!.hhh_isRefresh && !self.currentScrollView!.hhh_startRefresh) {
                        self.headerOriginYConstraint?.constant = py
        
                    } else {
        
                        if (self.currentScrollView!.contentOffset.y >= -headerViewHeight -  self.segmentBarHeight) {
                            self.currentScrollView!.hhh_startRefresh = false
                        }
                        self.headerOriginYConstraint?.constant = 0
                    }
                } else {            //向下滚动
                    if headerDisplayHeight+self.segmentBarHeight < -newOffsetY {
                        py = -self.headerViewHeight-self.segmentBarHeight-self.currentScrollView!.contentOffset.y;
        
                        if !self.allowPullToRefresh {
                            self.headerOriginYConstraint?.constant = py
        
                        } else if py < 0 {
                            self.headerOriginYConstraint?.constant = py
                        } else {
                            self.currentScrollView!.hhh_startRefresh = true
                            self.headerOriginYConstraint?.constant = 0;
                        }
                    }
                }

                let contentOffset = self.currentScrollView!.contentOffset
                delegate.pagingView?(self, scrollTopOffset: contentOffset.y)
            }

        } else if context == &ContextKey.HHHorizontalPagingViewInsetContext {
            if(self.allowPullToRefresh || self.currentScrollView!.contentOffset.y > -self.segmentBarHeight) {
                return
            }

            UIView.animate(withDuration: 0.2, animations: { 
                self.headerOriginYConstraint?.constant = -self.headerViewHeight-self.segmentBarHeight-self.currentScrollView!.contentOffset.y;
                self.layoutIfNeeded()
                self.headerView?.layoutIfNeeded()
                self.segmentView.layoutIfNeeded()
            })
        }
    }


    // MARK: -

    // 对headerView触发滚动的两种处理
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if point.x < 10 {
            return false
        }

        return true
    }


    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)

        if isGesturesSimulate {
            return view
        }
        // 如果处于刷新中，作用在headerView上的手势不响应在currentScrollView上
        if self.currentScrollView!.hhh_isRefresh {
            return view
        }

        if view?.isDescendant(of: headerView!) == true || view?.isDescendant(of: segmentView) == true {
            horizontalCollectionView.isScrollEnabled = false
            currentTouchView = nil
            currentTouchButton = nil

            for button in segmentButtons {
                if button == view {
                    currentTouchButton = button
                }
            }

            if currentTouchButton == nil {
                currentTouchView = view
                currentTouchViewPoint = convert(point, to: currentTouchView!)
            } else {
                return view
            }

            return currentScrollView
        }


        return view
    }

    func removeScrollView(_ scrollView: UIScrollView) {
        removeObserverFor(scrollView)
        if let index = contentViewArray.index(of: scrollView) {
            contentViewArray.remove(at: index)
        }
        let vc = viewControllerForView(scrollView)
        vc?.view.tag = 0
        scrollView.superview?.tag = 0
        vc?.view.superview?.tag = 0
        scrollView.removeFromSuperview()
        vc?.view.removeFromSuperview()
        vc?.removeFromParentViewController()
    }

    func removeObserverFor(_ scrollView: UIScrollView) {
        scrollView.panGestureRecognizer.removeObserver(self, forKeyPath: #keyPath(UIPanGestureRecognizer.state),
                                                       context: &ContextKey.HHHorizontalPagingViewPanContext)
        scrollView.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentOffset),
                                  context: &ContextKey.HHHorizontalPagingViewScrollContext)
        scrollView.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentInset),
                                  context: &ContextKey.HHHorizontalPagingViewInsetContext)
    }

    func reload() {
        headerView = delegate.headerViewInPagingView(self)
        headerViewHeight = delegate.headerHeightInPagingView(self)
        segmentButtons = delegate.segmentButtonsInPagingView(self)
        segmentBarHeight = delegate.segmentHeightInPagingView(self)
        configureHeaderView()
        configureSegmentView()

        // 防止该section 是计算得出会改变导致后面崩溃
        let section = delegate.numberOfSectionsInPagingView(self)
        registCellForm(0, to: section)
        horizontalCollectionView.reloadData()
    }


    func adjustOffsetContentView(_ scrollView: UIScrollView) {
        self.isSwitching = true;
        let headerViewDisplayHeight = self.headerViewHeight + (self.headerView?.frame.origin.y ?? 0)
        scrollView.layoutIfNeeded()


        if headerViewDisplayHeight != self.segmentTopSpace {// 还原位置
            scrollView.contentOffset = CGPoint(x: 0, y: -headerViewDisplayHeight - self.segmentBarHeight)
        } else if scrollView.contentOffset.y < -self.segmentBarHeight {
            scrollView.contentOffset = CGPoint(x: 0, y: -headerViewDisplayHeight - self.segmentBarHeight)
        } else {
            // self.segmentTopSpace
            scrollView.contentOffset = CGPoint(x: 0, y: scrollView.contentOffset.y - headerViewDisplayHeight + segmentTopSpace)
        }

        scrollView.delegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: false)

        DispatchQueue.main.async {
            self.isSwitching = false
        }
    }

    func viewControllerForView(_ view: UIView) -> UIViewController? {
        var next: UIView? = view
        while let hasNext = next {
            if let nextResponder = hasNext.next as? UIViewController {
                return nextResponder
            }

            next = hasNext.superview
        }

        return nil
    }

    func cellReuseIdentifierForIndex(_ index: Int) -> String {
        return "\(pagingCellIdentifier)_\(index)"
    }

    func scrollViewAtIndex(_ index: Int) -> UIScrollView {
        var scrollView: UIScrollView?
        for obj in contentViewArray {
            if obj.tag == pagingScrollViewTag + index {
                scrollView = obj
                break
            }
        }

        if scrollView == nil {
            scrollView = delegate.pagingView(self, viewAtIndex: index)
            configureContentView(scrollView!)
            scrollView!.tag = pagingScrollViewTag + index
            contentViewArray.append(scrollView!)
        }

        return scrollView!
    }

    func configureContentView(_ scrollView: UIScrollView?) {
        if let scrollView = scrollView {
            scrollView.contentInset = UIEdgeInsets(top: headerViewHeight + segmentBarHeight, left: 0, bottom: scrollView.contentInset.bottom, right: 0)
            scrollView.alwaysBounceVertical = true
            scrollView.showsVerticalScrollIndicator = false
            scrollView.contentOffset = CGPoint(x: 0, y: -self.headerViewHeight-self.segmentBarHeight)
            scrollView.panGestureRecognizer.addObserver(self, forKeyPath: "state", options: [.new, .old], context: &ContextKey.HHHorizontalPagingViewPanContext)
            scrollView.addObserver(self, forKeyPath: #keyPath(UIScrollView.contentOffset), options: [.new, .old], context: &ContextKey.HHHorizontalPagingViewScrollContext)
            scrollView.addObserver(self, forKeyPath: #keyPath(UIScrollView.contentInset), options: [.new, .old], context: &ContextKey.HHHorizontalPagingViewInsetContext)
        } else {
            currentScrollView = scrollView
        }
    }

    // 注册cell
    fileprivate func registCellForm(_ form: Int, to: Int) {
        for i in form..<to {
            horizontalCollectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseIdentifierForIndex(i))
        }
    }

    fileprivate func configureHeaderView() {
        headerView?.removeFromSuperview()

        if let headerView = headerView {
            headerView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(headerView)

            headerOriginYConstraint = NSLayoutConstraint(item: headerView, attribute: .top, relatedBy: .equal, toItem: self, attribute: .top, multiplier: 1.0, constant: 0)
            headerSizeHeightConstraint = NSLayoutConstraint(item: headerView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: headerViewHeight)
            addConstraints([
                NSLayoutConstraint(item: headerView, attribute: .left, relatedBy: .equal, toItem: self, attribute: .left, multiplier: 1.0, constant: 0),
                NSLayoutConstraint(item: headerView, attribute: .right, relatedBy: .equal, toItem: self, attribute: .right, multiplier: 1.0, constant: 0),
                headerOriginYConstraint!
            ])
            headerView.addConstraint(headerSizeHeightConstraint!)
            addGestureRecognizerAtHeaderView()
        }
    }

    fileprivate func addGestureRecognizerAtHeaderView() {

        if isGesturesSimulate == false {
            return
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.delegate = self
        headerView?.addGestureRecognizer(pan)
    }

    fileprivate func configureSegmentView() {
        segmentView.removeFromSuperview()
        segmentView = UIView()
        configureSegmentButtonLayout()
        segmentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(segmentView)
        addConstraints([
            NSLayoutConstraint(item: segmentView, attribute: .left, relatedBy: .equal, toItem: self, attribute: .left, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: segmentView, attribute: .right, relatedBy: .equal, toItem: self, attribute: .right, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: segmentView, attribute: .top, relatedBy: .equal, toItem: headerView ?? self, attribute: ((headerView != nil) ? NSLayoutAttribute.bottom: NSLayoutAttribute.top), multiplier: 1.0, constant: 0)
        ])
        segmentView.addConstraint(
            NSLayoutConstraint(item: segmentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: segmentBarHeight)
        )
    }

    fileprivate func configureSegmentButtonLayout() {
        if segmentButtons.count > 0 {
            var buttonTop: CGFloat = 0
            var buttonLeft: CGFloat = 0
            var buttonWidth: CGFloat = 0
            var buttonHeight: CGFloat = 0

            if segmentButtonSize.equalTo(CGSize.zero) {
                buttonWidth = UIScreen.main.bounds.width / CGFloat(segmentButtons.count)
                buttonHeight = segmentBarHeight
            } else {
                buttonWidth = segmentButtonSize.width
                buttonHeight = segmentButtonSize.height
                buttonTop = (segmentBarHeight - buttonHeight) / 2.0
                buttonLeft = (UIScreen.main.bounds.width - CGFloat(segmentButtons.count) * buttonWidth) / CGFloat(segmentButtons.count + 1)
            }

            segmentView.removeConstraints(segmentButtonConstraintArray)
            for i in 0..<segmentButtons.count {
                let segmentButton = segmentButtons[i]
                segmentButton.tag = pagingButtonTag + i
                segmentButton.addTarget(self, action: #selector(segmentButtonEvent(_:)), for: .touchUpInside)
                segmentView.addSubview(segmentButton)

                if i == 0 {
                    segmentButton.isSelected = true
                    currenPage = 0
                }
                segmentButton.translatesAutoresizingMaskIntoConstraints = false

                let topConstraint = NSLayoutConstraint(item: segmentButton, attribute: .top, relatedBy: .equal, toItem: segmentView, attribute: .top, multiplier: 1, constant: buttonTop)
                let leftConstraint = NSLayoutConstraint(item: segmentButton, attribute: .left, relatedBy: .equal, toItem: segmentView, attribute: .left, multiplier: 1.0, constant: CGFloat(i)*buttonWidth+buttonLeft*CGFloat(i)+buttonLeft)
                let widthConstraint = NSLayoutConstraint(item: segmentButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: buttonWidth)
                let heightConstraint = NSLayoutConstraint(item: segmentButton, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: buttonHeight)
                segmentButtonConstraintArray.append(topConstraint)
                segmentButtonConstraintArray.append(leftConstraint)
                segmentButtonConstraintArray.append(widthConstraint)
                segmentButtonConstraintArray.append(heightConstraint)

                segmentView.addConstraints([topConstraint, leftConstraint])
                segmentButton.addConstraints([widthConstraint, heightConstraint])

                if let _ = segmentButton.currentImage {
                    let imageWidth: CGFloat = segmentButton.imageView!.bounds.width
                    let labelWidth: CGFloat = segmentButton.titleLabel!.bounds.width
                    segmentButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: labelWidth + 5, bottom: 0, right: -labelWidth)
                    segmentButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: -imageWidth, bottom: 0, right: imageWidth)
                }
            }
        }
    }

    func segmentButtonEvent(_ segmentButton: UIButton) {

        let clickIndex = segmentButton.tag - pagingButtonTag
        if clickIndex >= delegate.numberOfSectionsInPagingView(self) {
            delegate.pagingView?(self, segmentDidSelected: segmentButton, atIndex: clickIndex)
            return
        }

        // 在当前页被点击
        if segmentButton.isSelected {
            delegate.pagingView?(self, segmentDidSelectedSameItem: segmentButton, atIndex: clickIndex)

            return
        }

        // 非当前页被点击
        horizontalCollectionView.scrollToItem(at: IndexPath(item: clickIndex, section: 0), at: .centeredHorizontally, animated: false)

        if currentScrollView!.contentOffset.y < -(headerViewHeight + segmentBarHeight) {
            currentScrollView!.setContentOffset(CGPoint(x: currentScrollView!.contentOffset.x, y: -headerViewHeight + segmentBarHeight),
                                                animated: false)
        }

        delegate.pagingView?(self, segmentDidSelected: segmentButton, atIndex: clickIndex)
        // 视图切换时执行代码
        didSwitchIndex(currenPage, to: clickIndex)
    }

    // 视图切换时执行代码

    func didSwitchIndex(_ aIndex: Int, to toIndex: Int) {
        currenPage = toIndex
        currentScrollView = scrollViewAtIndex(toIndex)

        if aIndex == toIndex {
            return
        }

        let oldScrollView = scrollViewAtIndex(aIndex)
        if oldScrollView.hhh_isRefresh {
            oldScrollView.hhh_isRefresh = false
            oldScrollView.hhh_startRefresh = false
            oldScrollView.setDragging(false)
            NotificationCenter.default.post(name: Notification.Name(rawValue: kHHHorizontalTakeBackRefreshEndNotification),
                                            object: scrollViewAtIndex(aIndex))
        }
        setSelectedButPage(toIndex)
        removeCacheScrollView()

        delegate.pagingView?(self, didSwitchIndex: aIndex, to: toIndex)
    }

    func removeCacheScrollView() {
        if contentViewArray.count <= maxCacheCout {
            return
        }
        releaseCache()
    }

    func setSelectedButPage(_ buttonPage: Int) {
        for b in segmentButtons {
            if b.tag - pagingButtonTag == buttonPage {
                b.isSelected = true
            } else {
                b.isSelected = false
            }
        }
        currenSelectedBut = buttonPage
    }

    func pullOffset() -> CGFloat {
        if _pullOffset == 0 {
            _pullOffset = delegate.headerHeightInPagingView(self) + delegate.segmentHeightInPagingView(self)
        }

        return _pullOffset
    }

    func scrollToIndex(_ pageIndex: Int) {
        segmentButtonEvent(segmentButtons[pageIndex])
    }

    func scrollEnable(_ enable: Bool) {
        if enable {
            segmentView.isUserInteractionEnabled = true
            horizontalCollectionView.isScrollEnabled = true
        } else {
            segmentView.isUserInteractionEnabled = false
            horizontalCollectionView.isScrollEnabled = false
        }
    }

}









