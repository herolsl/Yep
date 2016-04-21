//
//  SearchFeedsViewController.swift
//  Yep
//
//  Created by NIX on 16/4/11.
//  Copyright © 2016年 Catch Inc. All rights reserved.
//

import UIKit
import RealmSwift
import AVFoundation
import MapKit
import Ruler

class SearchFeedsViewController: UIViewController {

    static let feedNormalImagesCountThreshold: Int = Ruler.UniversalHorizontal(3, 4, 4, 3, 4).value

    var originalNavigationControllerDelegate: UINavigationControllerDelegate?
    private var feedsSearchTransition: FeedsSearchTransition?

    private var searchBarCancelButtonEnabledObserver: ObjectKeypathObserver?
    @IBOutlet weak var searchBar: UISearchBar! {
        didSet {
            searchBar.placeholder = NSLocalizedString("Search Feeds", comment: "")
            searchBar.setSearchFieldBackgroundImage(UIImage(named: "searchbar_textfield_background"), forState: .Normal)
            searchBar.returnKeyType = .Done
        }
    }
    @IBOutlet weak var searchBarBottomLineView: HorizontalLineView! {
        didSet {
            searchBarBottomLineView.lineColor = UIColor(white: 0.68, alpha: 1.0)
        }
    }
    @IBOutlet weak var searchBarTopConstraint: NSLayoutConstraint!

    private let searchedFeedBasicCellID = "SearchedFeedBasicCell"
    private let searchedFeedNormalImagesCellID = "SearchedFeedNormalImagesCell"
    private let searchedFeedAnyImagesCellID = "SearchedFeedAnyImagesCell"
    private let searchedFeedGithubRepoCellID = "SearchedFeedGithubRepoCell"
    private let searchedFeedDribbbleShotCellID = "SearchedFeedDribbbleShotCell"
    private let searchedFeedVoiceCellID = "SearchedFeedVoiceCell"
    private let searchedFeedLocationCellID = "SearchedFeedLocationCell"
    private let searchedFeedURLCellID = "SearchedFeedURLCell"
    private let loadMoreTableViewCellID = "LoadMoreTableViewCell"

    private lazy var noFeedsFooterView: InfoView = InfoView(NSLocalizedString("No Feeds.", comment: ""))

    var feeds = [DiscoveredFeed]() {
        didSet {
            if feeds.isEmpty {
                let footerView = SearchFeedsFooterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
                feedsTableView.tableFooterView = footerView
            } else {
                feedsTableView.tableFooterView = nil
            }
        }
    }

    let needShowSkill: Bool = false

    private var selectedIndexPathForMenu: NSIndexPath?

    @IBOutlet weak var feedsTableView: UITableView!  {
        didSet {
            feedsTableView.backgroundColor = UIColor.whiteColor()
            feedsTableView.tableFooterView = UIView()
            feedsTableView.separatorColor = UIColor.yepCellSeparatorColor()
            feedsTableView.separatorStyle = UITableViewCellSeparatorStyle.SingleLine

            feedsTableView.registerClass(SearchedFeedBasicCell.self, forCellReuseIdentifier: searchedFeedBasicCellID)
            feedsTableView.registerClass(SearchedFeedNormalImagesCell.self, forCellReuseIdentifier: searchedFeedNormalImagesCellID)
            feedsTableView.registerClass(SearchedFeedAnyImagesCell.self, forCellReuseIdentifier: searchedFeedAnyImagesCellID)
            feedsTableView.registerClass(SearchedFeedGithubRepoCell.self, forCellReuseIdentifier: searchedFeedGithubRepoCellID)
            feedsTableView.registerClass(SearchedFeedDribbbleShotCell.self, forCellReuseIdentifier: searchedFeedDribbbleShotCellID)
            feedsTableView.registerClass(SearchedFeedVoiceCell.self, forCellReuseIdentifier: searchedFeedVoiceCellID)
            feedsTableView.registerClass(SearchedFeedLocationCell.self, forCellReuseIdentifier: searchedFeedLocationCellID)
            feedsTableView.registerClass(SearchedFeedURLCell.self, forCellReuseIdentifier: searchedFeedURLCellID)

            feedsTableView.registerNib(UINib(nibName: loadMoreTableViewCellID, bundle: nil), forCellReuseIdentifier: loadMoreTableViewCellID)

            feedsTableView.keyboardDismissMode = .OnDrag
        }
    }

    private var keyword: String? {
        didSet {
            if keyword == nil {
                clearSearchResults()
            }
            if let keyword = keyword where keyword.isEmpty {
                clearSearchResults()
            }
        }
    }
    private var searchTask: CancelableTask?

    private struct LayoutPool {

        private var feedCellLayoutHash = [String: SearchedFeedCellLayout]()

        private mutating func feedCellLayoutOfFeed(feed: DiscoveredFeed) -> SearchedFeedCellLayout {
            let key = feed.id

            if let layout = feedCellLayoutHash[key] {
                return layout

            } else {
                let layout = SearchedFeedCellLayout(feed: feed)

                updateFeedCellLayout(layout, forFeed: feed)

                return layout
            }
        }

        private mutating func updateFeedCellLayout(layout: SearchedFeedCellLayout, forFeed feed: DiscoveredFeed) {

            let key = feed.id

            if !key.isEmpty {
                feedCellLayoutHash[key] = layout
            }

            //println("feedCellLayoutHash.count: \(feedCellLayoutHash.count)")
        }

        private mutating func heightOfFeed(feed: DiscoveredFeed) -> CGFloat {

            let layout = feedCellLayoutOfFeed(feed)
            return layout.height
        }
    }
    private static var layoutPool = LayoutPool()

    // MARK: Audio Play

    private var audioPlayedDurations = [String: NSTimeInterval]()

    private weak var feedAudioPlaybackTimer: NSTimer?

    private func audioPlayedDurationOfFeedAudio(feedAudio: FeedAudio) -> NSTimeInterval {
        let key = feedAudio.feedID

        if !key.isEmpty {
            if let playedDuration = audioPlayedDurations[key] {
                return playedDuration
            }
        }

        return 0
    }

    private func setAudioPlayedDuration(audioPlayedDuration: NSTimeInterval, ofFeedAudio feedAudio: FeedAudio) {
        let key = feedAudio.feedID
        if !key.isEmpty {
            audioPlayedDurations[key] = audioPlayedDuration
        }

        // recover audio cells' UI

        if audioPlayedDuration == 0 {

            let feedID = feedAudio.feedID

            for index in 0..<feeds.count {
                let feed = feeds[index]
                if feed.id == feedID {

                    let indexPath = NSIndexPath(forRow: index, inSection: Section.Feed.rawValue)

                    if let cell = feedsTableView.cellForRowAtIndexPath(indexPath) as? SearchedFeedVoiceCell {
                        cell.audioPlayedDuration = 0
                    }
                    
                    break
                }
            }
        }
    }

    private func updateCellOfFeedAudio(feedAudio: FeedAudio, withCurrentTime currentTime: NSTimeInterval) {

        let feedID = feedAudio.feedID

        for index in 0..<feeds.count {
            let feed = feeds[index]
            if feed.id == feedID {

                let indexPath = NSIndexPath(forRow: index, inSection: Section.Feed.rawValue)

                if let cell = feedsTableView.cellForRowAtIndexPath(indexPath) as? SearchedFeedVoiceCell {
                    cell.audioPlayedDuration = currentTime
                }

                break
            }
        }
    }

    @objc private func updateAudioPlaybackProgress(timer: NSTimer) {

        guard let playingFeedAudio = YepAudioService.sharedManager.playingFeedAudio else {
            return
        }

        let currentTime = YepAudioService.sharedManager.audioPlayCurrentTime
        setAudioPlayedDuration(currentTime, ofFeedAudio: playingFeedAudio )
        updateCellOfFeedAudio(playingFeedAudio, withCurrentTime: currentTime)
    }

    @objc private func updateOnlineAudioPlaybackProgress(timer: NSTimer) {

        guard let playingFeedAudio = YepAudioService.sharedManager.playingFeedAudio else {
            return
        }

        let currentTime = YepAudioService.sharedManager.aduioOnlinePlayCurrentTime.seconds
        setAudioPlayedDuration(currentTime, ofFeedAudio: playingFeedAudio )
        updateCellOfFeedAudio(playingFeedAudio, withCurrentTime: currentTime)
    }

    // MARK: Life Circle

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
        println("deinit SearchFeeds")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        feeds = []

        searchBarBottomLineView.alpha = 0

        feedsTableView.layoutMargins = UIEdgeInsetsZero
        feedsTableView.separatorInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(SearchFeedsViewController.didRecieveMenuWillShowNotification(_:)), name: UIMenuControllerWillShowMenuNotification, object: nil)

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(SearchFeedsViewController.didRecieveMenuWillHideNotification(_:)), name: UIMenuControllerWillHideMenuNotification, object: nil)

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(SearchFeedsViewController.feedAudioDidFinishPlaying(_:)), name: AVPlayerItemDidPlayToEndTimeNotification, object: nil)
    }

    private var isFirstAppear = true

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setNavigationBarHidden(true, animated: true)

        if isFirstAppear {
            delay(0.3) { [weak self] in
                self?.searchBar.becomeFirstResponder()
            }
            delay(0.4) { [weak self] in
                self?.searchBar.setShowsCancelButton(true, animated: true)

                self?.searchBarCancelButtonEnabledObserver = self?.searchBar.yep_makeSureCancelButtonAlwaysEnabled()
            }
        }
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        if let delegate = feedsSearchTransition {
            navigationController?.delegate = delegate
        }

        UIView.animateWithDuration(0.25, delay: 0.0, options: .CurveEaseInOut, animations: { [weak self] _ in
            self?.searchBarTopConstraint.constant = 0
            self?.view.layoutIfNeeded()
        }, completion: nil)

        isFirstAppear = false
    }

    // MARK: - Private

    private var canLoadMore: Bool = false
    private var currentPageIndex = 1
    private var isFetchingFeeds = false
    enum SearchFeedsMode {
        case Init
        case LoadMore
    }
    private func searchFeedsWithKeyword(keyword: String, mode: SearchFeedsMode, finish: (() -> Void)? = nil) {

        if isFetchingFeeds {
            finish?()
            return
        }

        isFetchingFeeds = true

        switch mode {
        case .Init:
            canLoadMore = true
            currentPageIndex = 1
        case .LoadMore:
            currentPageIndex += 1
        }

        let failureHandler: FailureHandler = { reason, errorMessage in

            dispatch_async(dispatch_get_main_queue()) { [weak self] in

                self?.isFetchingFeeds = false

                finish?()
            }

            defaultFailureHandler(reason: reason, errorMessage: errorMessage)
        }

        let perPage: Int = 30

        feedsWithKeyword(keyword, pageIndex: currentPageIndex, perPage: perPage, failureHandler: failureHandler) { [weak self] feeds in

            dispatch_async(dispatch_get_main_queue()) { [weak self] in

                guard let strongSelf = self else {
                    return
                }

                self?.isFetchingFeeds = false

                finish?()

                let newFeeds = feeds
                let oldFeeds = strongSelf.feeds

                self?.canLoadMore = newFeeds.count == perPage

                var wayToUpdate: UITableView.WayToUpdate = .None

                if strongSelf.feeds.isEmpty {
                    wayToUpdate = .ReloadData
                }

                switch mode {

                case .Init:
                    strongSelf.feeds = newFeeds

                    wayToUpdate = .ReloadData

                case .LoadMore:
                    let oldFeedsCount = oldFeeds.count

                    let oldFeedIDSet = Set<String>(strongSelf.feeds.map({ $0.id }))
                    var realNewFeeds = [DiscoveredFeed]()
                    for feed in newFeeds {
                        if !oldFeedIDSet.contains(feed.id) {
                            realNewFeeds.append(feed)
                        }
                    }
                    strongSelf.feeds += realNewFeeds

                    let newFeedsCount = strongSelf.feeds.count

                    let indexPaths = Array(oldFeedsCount..<newFeedsCount).map({ NSIndexPath(forRow: $0, inSection: Section.Feed.rawValue) })
                    if !indexPaths.isEmpty {
                        wayToUpdate = .Insert(indexPaths)
                    }
                }

                wayToUpdate.performWithTableView(strongSelf.feedsTableView)
            }
        }
    }

    private func hideKeyboard() {

        searchBar.resignFirstResponder()
    }

    private func updateResultsTableView(scrollsToTop scrollsToTop: Bool = false) {
        dispatch_async(dispatch_get_main_queue()) { [weak self] in
            self?.feedsTableView.reloadData()

            if scrollsToTop {
                self?.feedsTableView.yep_scrollsToTop()
            }
        }
    }

    // MARK: - Navigation

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {

        guard let identifier = segue.identifier else {
            return
        }

        func hackNavigationDelegate() {
            // 记录原始的 feedsSearchTransition 以便 pop 后恢复
            feedsSearchTransition = navigationController?.delegate as? FeedsSearchTransition

            println("originalNavigationControllerDelegate: \(originalNavigationControllerDelegate)")
            navigationController?.delegate = originalNavigationControllerDelegate
        }
        
        switch identifier {

        case "showProfile":
            let vc = segue.destinationViewController as! ProfileViewController

            if let indexPath = sender as? NSIndexPath, section = Section(rawValue: indexPath.section) {

                switch section {
                case .Feed:
                    let discoveredUser = feeds[indexPath.row].creator
                    vc.profileUser = ProfileUser.DiscoveredUserType(discoveredUser)
                case .LoadMore:
                    break
                }
            }

            vc.hidesBottomBarWhenPushed = true

            vc.setBackButtonWithTitle()

            hackNavigationDelegate()

        case "showConversation":

            let vc = segue.destinationViewController as! ConversationViewController

            guard let
                indexPath = sender as? NSIndexPath,
                feed = feeds[safe: indexPath.row],
                realm = try? Realm() else {
                    return
            }

            realm.beginWrite()
            let feedConversation = vc.prepareConversationForFeed(feed, inRealm: realm)
            let _ = try? realm.commitWrite()

            vc.conversation = feedConversation
            vc.conversationFeed = ConversationFeed.DiscoveredFeedType(feed)

            vc.afterDeletedFeedAction = { feedID in
                dispatch_async(dispatch_get_main_queue()) { [weak self] in
                    if let strongSelf = self {
                        var deletedFeed: DiscoveredFeed?
                        for feed in strongSelf.feeds {
                            if feed.id == feedID {
                                deletedFeed = feed
                                break
                            }
                        }

                        if let deletedFeed = deletedFeed, index = strongSelf.feeds.indexOf(deletedFeed) {
                            strongSelf.feeds.removeAtIndex(index)

                            let indexPath = NSIndexPath(forRow: index, inSection: Section.Feed.rawValue)
                            strongSelf.feedsTableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .None)

                            return
                        }
                    }

                    // 若不能单项删除，给点时间给服务器，防止请求回来的 feeds 包含被删除的
                    delay(1) {
                        //self?.updateFeeds()
                    }

                    println("afterDeletedFeedAction")
                }
            }

            vc.conversationDirtyAction = { [weak self] groupID in

                groupWithGroupID(groupID: groupID, failureHandler: nil, completion: { [weak self] groupInfo in

                    if let feedInfo = groupInfo["topic"] as? JSONDictionary {

                        guard let strongSelf = self, feed = DiscoveredFeed.fromFeedInfo(feedInfo, groupInfo: groupInfo) else {
                            return
                        }

                        if let index = strongSelf.feeds.indexOf(feed) {
                            if strongSelf.feeds[index].messagesCount != feed.messagesCount {
                                strongSelf.feeds[index].messagesCount = feed.messagesCount

                                let indexPath = NSIndexPath(forRow: index, inSection: Section.Feed.rawValue)
                                let wayToUpdate: UITableView.WayToUpdate = .ReloadIndexPaths([indexPath])
                                dispatch_async(dispatch_get_main_queue()) {
                                    wayToUpdate.performWithTableView(strongSelf.feedsTableView)
                                }
                            }
                        }
                    }
                })

                println("conversationDirtyAction")
            }

            vc.syncPlayFeedAudioAction = { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.feedAudioPlaybackTimer = NSTimer.scheduledTimerWithTimeInterval(0.02, target: strongSelf, selector: #selector(SearchFeedsViewController.updateOnlineAudioPlaybackProgress(_:)), userInfo: nil, repeats: true)
            }

            hackNavigationDelegate()
            
        default:
            break
        }
    }
}

// MARK: - UISearchBarDelegate

extension SearchFeedsViewController: UISearchBarDelegate {

    func searchBarShouldBeginEditing(searchBar: UISearchBar) -> Bool {

        UIView.animateWithDuration(0.1, delay: 0.0, options: .CurveEaseInOut, animations: { [weak self] _ in
            self?.searchBarBottomLineView.alpha = 1
        }, completion: { finished in
        })

        return true
    }

    func searchBarCancelButtonClicked(searchBar: UISearchBar) {

        searchBar.text = nil
        searchBar.resignFirstResponder()

        UIView.animateWithDuration(0.1, delay: 0.0, options: .CurveEaseInOut, animations: { [weak self] _ in
            self?.searchBarBottomLineView.alpha = 0
        }, completion: { finished in
        })

        navigationController?.popViewControllerAnimated(true)
    }

    func searchBar(searchBar: UISearchBar, textDidChange searchText: String) {

        println("try search feeds with keyword: \(searchText)")

        cancel(searchTask)

        if searchText.isEmpty {
            self.keyword = nil
            return
        }

        searchTask = delay(0.5) { [weak self] in
            self?.updateSearchResultsWithText(searchText)
        }
    }

    func searchBarSearchButtonClicked(searchBar: UISearchBar) {

        hideKeyboard()
    }

    private func clearSearchResults() {

        feeds = []

        updateResultsTableView(scrollsToTop: true)
    }

    private func updateSearchResultsWithText(searchText: String) {

        let searchText = searchText.trimming(.Whitespace)

        // 不要重复搜索一样的内容
        if let keyword = self.keyword where keyword == searchText {
            return
        }

        self.keyword = searchText

        guard !searchText.isEmpty else {
            return
        }

        searchFeedsWithKeyword(searchText, mode: .Init)
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension SearchFeedsViewController: UITableViewDataSource, UITableViewDelegate {

    private enum Section: Int {
        case Feed
        case LoadMore
    }

    func numberOfSectionsInTableView(tableView: UITableView) -> Int {

        return 2
    }

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

        guard let section = Section(rawValue: section) else {
            return 0
        }

        switch section {
        case .Feed:
            return feeds.count
        case .LoadMore:
            return feeds.isEmpty ? 0 : 1
        }
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {

        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        func cellForFeed(feed: DiscoveredFeed) -> UITableViewCell {

            switch feed.kind {

            case .Text:
                let cell = tableView.dequeueReusableCellWithIdentifier(searchedFeedBasicCellID) as! SearchedFeedBasicCell
                return cell

            case .URL:
                let cell = tableView.dequeueReusableCellWithIdentifier(searchedFeedURLCellID) as! SearchedFeedURLCell
                return cell

            case .Image:
                if feed.imageAttachmentsCount <= SearchFeedsViewController.feedNormalImagesCountThreshold {
                    let cell = tableView.dequeueReusableCellWithIdentifier(searchedFeedNormalImagesCellID) as! SearchedFeedNormalImagesCell
                    return cell

                } else {
                    let cell = tableView.dequeueReusableCellWithIdentifier(searchedFeedAnyImagesCellID) as! SearchedFeedAnyImagesCell
                    return cell
                }

            case .GithubRepo:
                let cell = tableView.dequeueReusableCellWithIdentifier(searchedFeedGithubRepoCellID) as! SearchedFeedGithubRepoCell
                return cell

            case .DribbbleShot:
                let cell = tableView.dequeueReusableCellWithIdentifier(searchedFeedDribbbleShotCellID) as! SearchedFeedDribbbleShotCell
                return cell

            case .Audio:
                let cell = tableView.dequeueReusableCellWithIdentifier(searchedFeedVoiceCellID) as! SearchedFeedVoiceCell
                return cell

            case .Location:
                let cell = tableView.dequeueReusableCellWithIdentifier(searchedFeedLocationCellID) as! SearchedFeedLocationCell
                return cell

            default:
                let cell = tableView.dequeueReusableCellWithIdentifier(searchedFeedBasicCellID) as! SearchedFeedBasicCell
                return cell
            }
        }

        switch section {

        case .Feed:

            let feed = feeds[indexPath.row]
            return cellForFeed(feed)

        case .LoadMore:

            let cell = tableView.dequeueReusableCellWithIdentifier(loadMoreTableViewCellID) as! LoadMoreTableViewCell
            return cell
        }
    }

    func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {

        guard let section = Section(rawValue: indexPath.section) else {
            return
        }

        func configureFeedCell(cell: UITableViewCell, withFeed feed: DiscoveredFeed) {

            guard let cell = cell as? SearchedFeedBasicCell else {
                return
            }

            cell.tapAvatarAction = { [weak self] cell in
                if let indexPath = tableView.indexPathForCell(cell) { // 不直接捕捉 indexPath
                    println("tapAvatarAction indexPath: \(indexPath.section), \(indexPath.row)")
                    self?.hideKeyboard()
                    self?.performSegueWithIdentifier("showProfile", sender: indexPath)
                }
            }

            // simulate select effects when tap on messageTextView or cell.mediaCollectionView's space part
            // 不能直接捕捉 indexPath，不然新插入后，之前捕捉的 indexPath 不能代表 cell 的新位置，模拟点击会错位到其它 cell
            cell.touchesBeganAction = { [weak self] cell in
                guard let indexPath = tableView.indexPathForCell(cell) else {
                    return
                }
                self?.tableView(tableView, willSelectRowAtIndexPath: indexPath)
                tableView.selectRowAtIndexPath(indexPath, animated: false, scrollPosition: .None)
            }
            cell.touchesEndedAction = { [weak self] cell in
                guard let indexPath = tableView.indexPathForCell(cell) else {
                    return
                }
                delay(0.03) { [weak self] in
                    self?.tableView(tableView, didSelectRowAtIndexPath: indexPath)
                }
            }
            cell.touchesCancelledAction = { cell in
                guard let indexPath = tableView.indexPathForCell(cell) else {
                    return
                }
                tableView.deselectRowAtIndexPath(indexPath, animated: true)
            }

            let layout = SearchFeedsViewController.layoutPool.feedCellLayoutOfFeed(feed)

            switch feed.kind {

            case .Text:

                cell.configureWithFeed(feed, layout: layout, keyword: keyword)

            case .URL:

                guard let cell = cell as? SearchedFeedURLCell else {
                    break
                }

                cell.configureWithFeed(feed, layout: layout, keyword: keyword)

                cell.tapURLInfoAction = { [weak self] URL in
                    println("tapURLInfoAction URL: \(URL)")
                    self?.yep_openURL(URL)
                }

            case .Image:

                let tapMediaAction: FeedTapMediaAction = { [weak self] transitionView, image, attachments, index in

                    guard image != nil else {
                        return
                    }

                    let vc = UIStoryboard(name: "MediaPreview", bundle: nil).instantiateViewControllerWithIdentifier("MediaPreviewViewController") as! MediaPreviewViewController

                    vc.previewMedias = attachments.map({ PreviewMedia.AttachmentType(attachment: $0) })
                    vc.startIndex = index

                    let transitionView = transitionView
                    let frame = transitionView.convertRect(transitionView.bounds, toView: self?.view)
                    vc.previewImageViewInitalFrame = frame
                    vc.bottomPreviewImage = image

                    vc.transitionView = transitionView

                    delay(0) {
                        transitionView.alpha = 0 // 放到下一个 Runloop 避免太快消失产生闪烁
                    }
                    vc.afterDismissAction = { [weak self] in
                        transitionView.alpha = 1
                        self?.view.window?.makeKeyAndVisible()
                    }

                    mediaPreviewWindow.rootViewController = vc
                    mediaPreviewWindow.windowLevel = UIWindowLevelAlert - 1
                    mediaPreviewWindow.makeKeyAndVisible()
                }

                if feed.imageAttachmentsCount <= SearchFeedsViewController.feedNormalImagesCountThreshold {

                    guard let cell = cell as? SearchedFeedNormalImagesCell else {
                        break
                    }

                    cell.configureWithFeed(feed, layout: layout, keyword: keyword)

                    cell.tapMediaAction = tapMediaAction

                } else {
                    guard let cell = cell as? SearchedFeedAnyImagesCell else {
                        break
                    }

                    cell.configureWithFeed(feed, layout: layout, keyword: keyword)

                    cell.tapMediaAction = tapMediaAction
                }

            case .GithubRepo:

                guard let cell = cell as? SearchedFeedGithubRepoCell else {
                    break
                }

                cell.configureWithFeed(feed, layout: layout, keyword: keyword)

                cell.tapGithubRepoLinkAction = { [weak self] URL in
                    self?.yep_openURL(URL)
                }

            case .DribbbleShot:

                guard let cell = cell as? SearchedFeedDribbbleShotCell else {
                    break
                }

                cell.configureWithFeed(feed, layout: layout, keyword: keyword)

                cell.tapDribbbleShotLinkAction = { [weak self] URL in
                    self?.yep_openURL(URL)
                }

                cell.tapDribbbleShotMediaAction = { [weak self] transitionView, image, imageURL, linkURL in

                    guard image != nil else {
                        return
                    }

                    let vc = UIStoryboard(name: "MediaPreview", bundle: nil).instantiateViewControllerWithIdentifier("MediaPreviewViewController") as! MediaPreviewViewController

                    vc.previewMedias = [PreviewMedia.WebImage(imageURL: imageURL, linkURL: linkURL)]
                    vc.startIndex = 0

                    let transitionView = transitionView
                    let frame = transitionView.convertRect(transitionView.bounds, toView: self?.view)
                    vc.previewImageViewInitalFrame = frame
                    vc.bottomPreviewImage = image

                    delay(0) {
                        transitionView.alpha = 0 // 放到下一个 Runloop 避免太快消失产生闪烁
                    }
                    vc.afterDismissAction = { [weak self] in
                        transitionView.alpha = 1
                        self?.view.window?.makeKeyAndVisible()
                    }

                    mediaPreviewWindow.rootViewController = vc
                    mediaPreviewWindow.windowLevel = UIWindowLevelAlert - 1
                    mediaPreviewWindow.makeKeyAndVisible()
                }

            case .Audio:

                guard let cell = cell as? SearchedFeedVoiceCell else {
                    break
                }

                cell.configureWithFeed(feed, layout: layout, keyword: keyword)

                cell.playOrPauseAudioAction = { [weak self] cell in

                    guard let realm = try? Realm(), feedAudio = FeedAudio.feedAudioWithFeedID(feed.id, inRealm: realm) else {
                        return
                    }

                    let play: () -> Void = { [weak self] in

                        if let strongSelf = self {

                            let audioPlayedDuration = strongSelf.audioPlayedDurationOfFeedAudio(feedAudio)
                            YepAudioService.sharedManager.playOnlineAudioWithFeedAudio(feedAudio, beginFromTime: audioPlayedDuration, delegate: strongSelf, success: {
                                println("playOnlineAudioWithFeedAudio success!")

                                strongSelf.feedAudioPlaybackTimer?.invalidate()

                                let playbackTimer = NSTimer.scheduledTimerWithTimeInterval(0.02, target: strongSelf, selector: #selector(SearchFeedsViewController.updateOnlineAudioPlaybackProgress(_:)), userInfo: nil, repeats: true)
                                YepAudioService.sharedManager.playbackTimer = playbackTimer

                                cell.audioPlaying = true
                            })
                        }
                    }

                    if let strongSelf = self {

                        // 如果在播放，就暂停
                        if let playingFeedAudio = YepAudioService.sharedManager.playingFeedAudio, onlineAudioPlayer = YepAudioService.sharedManager.onlineAudioPlayer where onlineAudioPlayer.yep_playing {

                            onlineAudioPlayer.pause()

                            if let playbackTimer = YepAudioService.sharedManager.playbackTimer {
                                playbackTimer.invalidate()
                            }

                            let feedID = playingFeedAudio.feedID
                            for index in 0..<strongSelf.feeds.count {
                                let feed = strongSelf.feeds[index]
                                if feed.id == feedID {

                                    let indexPath = NSIndexPath(forRow: index, inSection: Section.Feed.rawValue)

                                    if let cell = strongSelf.feedsTableView.cellForRowAtIndexPath(indexPath) as? FeedVoiceCell {
                                        cell.audioPlaying = false
                                    }

                                    break
                                }
                            }

                            if let playingFeedAudio = YepAudioService.sharedManager.playingFeedAudio where playingFeedAudio.feedID == feed.id {
                                YepAudioService.sharedManager.tryNotifyOthersOnDeactivation()

                            } else {
                                // 暂停的是别人，咱开始播放
                                play()
                            }

                        } else {
                            // 直接播放
                            play()
                        }
                    }
                }

            case .Location:

                guard let cell = cell as? SearchedFeedLocationCell else {
                    break
                }

                cell.configureWithFeed(feed, layout: layout, keyword: keyword)

                cell.tapLocationAction = { locationName, locationCoordinate in

                    let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: locationCoordinate, addressDictionary: nil))
                    mapItem.name = locationName

                    mapItem.openInMapsWithLaunchOptions(nil)
                }

            default:
                break
            }
        }

        switch section {

        case .Feed:

            let feed = feeds[indexPath.row]
            configureFeedCell(cell, withFeed: feed)

        case .LoadMore:

            guard let cell = cell as? LoadMoreTableViewCell else {
                break
            }

            guard canLoadMore else {
                cell.isLoading = false
                break
            }

            println("search more feeds")

            if !cell.isLoading {
                cell.isLoading = true
            }

            if let keyword = self.keyword {
                searchFeedsWithKeyword(keyword, mode: .LoadMore, finish: { [weak cell] in
                    cell?.isLoading = false
                })
            } else {
                cell.isLoading = false
            }
        }
    }

    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {

        guard let section = Section(rawValue: indexPath.section) else {
            return 0
        }

        switch section {

        case .Feed:
            let feed = feeds[indexPath.row]
            return SearchFeedsViewController.layoutPool.heightOfFeed(feed)

        case .LoadMore:
            return 60
        }
    }

    func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
        return indexPath
    }

    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {

        defer {
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
        }

        hideKeyboard()

        guard let section = Section(rawValue: indexPath.section) else {
            return
        }

        switch section {

        case .Feed:
            performSegueWithIdentifier("showConversation", sender: indexPath)

        case .LoadMore:
            break
        }
    }

    // Report

    func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {

        guard let section = Section(rawValue: indexPath.section) else {
            return false
        }

        switch section {

        case .Feed:
            let feed = feeds[indexPath.item]
            if feed.creator.id == YepUserDefaults.userID.value {
                return false
            } else {
                return true
            }

        case .LoadMore:
            return false
        }
    }

    func tableView(tableView: UITableView, editActionsForRowAtIndexPath indexPath: NSIndexPath) -> [UITableViewRowAction]? {

        guard let section = Section(rawValue: indexPath.section) else {
            return nil
        }

        if case .Feed = section {

            let reportAction = UITableViewRowAction(style: .Default, title: NSLocalizedString("Report", comment: "")) { [weak self] action, indexPath in

                if let feed = self?.feeds[indexPath.row] {
                    self?.report(.Feed(feedID: feed.id))
                }

                tableView.setEditing(false, animated: true)
            }

            return [reportAction]
        }

        return nil
    }

    func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
    }
    
    // MARK: Copy Message
    
    @objc private func didRecieveMenuWillHideNotification(notification: NSNotification) {
        
        selectedIndexPathForMenu = nil
    }
    
    @objc private func didRecieveMenuWillShowNotification(notification: NSNotification) {
        
        guard let menu = notification.object as? UIMenuController, selectedIndexPathForMenu = selectedIndexPathForMenu, cell = feedsTableView.cellForRowAtIndexPath(selectedIndexPathForMenu) as? SearchedFeedBasicCell else {
            return
        }
        
        let bubbleFrame = cell.convertRect(cell.messageTextView.frame, toView: view)
        
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIMenuControllerWillShowMenuNotification, object: nil)
        
        menu.setTargetRect(bubbleFrame, inView: view)
        menu.setMenuVisible(true, animated: true)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(SearchFeedsViewController.didRecieveMenuWillShowNotification(_:)), name: UIMenuControllerWillShowMenuNotification, object: nil)
        
        feedsTableView.deselectRowAtIndexPath(selectedIndexPathForMenu, animated: true)
    }
    
    func tableView(tableView: UITableView, shouldShowMenuForRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        
        defer {
            selectedIndexPathForMenu = indexPath
        }
        
        guard let _ = tableView.cellForRowAtIndexPath(indexPath) as? FeedBasicCell else {
            return false
        }
        
        return true
    }
    
    func tableView(tableView: UITableView, canPerformAction action: Selector, forRowAtIndexPath indexPath: NSIndexPath, withSender sender: AnyObject?) -> Bool {
        
        if action == #selector(NSObject.copy(_:)) {
            return true
        }
        
        return false
    }
    
    func tableView(tableView: UITableView, performAction action: Selector, forRowAtIndexPath indexPath: NSIndexPath, withSender sender: AnyObject?) {
        
        guard let cell = tableView.cellForRowAtIndexPath(indexPath) as? FeedBasicCell else {
            return
        }
        
        if action == #selector(NSObject.copy(_:)) {
            UIPasteboard.generalPasteboard().string = cell.messageTextView.text
        }
    }
}

// MARK: Audio Finish Playing

extension SearchFeedsViewController {

    private func feedAudioDidFinishPlaying() {

        if let playbackTimer = YepAudioService.sharedManager.playbackTimer {
            playbackTimer.invalidate()
        }

        if let playingFeedAudio = YepAudioService.sharedManager.playingFeedAudio {
            setAudioPlayedDuration(0, ofFeedAudio: playingFeedAudio)
            println("setAudioPlayedDuration to 0")
        }

        YepAudioService.sharedManager.resetToDefault()
    }

    @objc private func feedAudioDidFinishPlaying(notification: NSNotification) {
        feedAudioDidFinishPlaying()
    }
}

// MARK: AVAudioPlayerDelegate

extension SearchFeedsViewController: AVAudioPlayerDelegate {

    func audioPlayerDidFinishPlaying(player: AVAudioPlayer, successfully flag: Bool) {

        println("audioPlayerDidFinishPlaying \(flag)")
        
        feedAudioDidFinishPlaying()
    }
}
