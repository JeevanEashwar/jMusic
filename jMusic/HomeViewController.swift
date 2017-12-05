//
//  FirstViewController.swift
//  jMusic
//
//  Created by Jeevan on 22/07/17.
//  Copyright © 2017 personal. All rights reserved.
//

import UIKit
import AVFoundation
import MediaPlayer
extension UILabel {
    func countLabelLines() -> Int {
        // Call self.layoutIfNeeded() if your view is uses auto layout
        let myText = self.text! as NSString
        let attributes = [NSFontAttributeName : self.font]
        
        let labelSize = myText.boundingRect(with: CGSize(width: self.bounds.width, height: CGFloat.greatestFiniteMagnitude), options: NSStringDrawingOptions.usesLineFragmentOrigin, attributes: attributes, context: nil)
        return Int(ceil(CGFloat(labelSize.height) / self.font.lineHeight))
    }
    func isTruncated() -> Bool {
        
        if (self.countLabelLines() > self.numberOfLines) {
            return true
        }
        return false
    }
}
extension AVPlayer {
    var isReadyToPlay:Bool {
        let timeRange = currentItem?.loadedTimeRanges.first as? CMTimeRange
        guard let duration = timeRange?.duration else { return false }
        let timeLoaded = Int(duration.value) / Int(duration.timescale) // value/timescale = seconds
        let loaded = timeLoaded > 0
        
        return status == .readyToPlay && loaded
    }
}
class HomeViewController: UIViewController,AVAudioPlayerDelegate,UICollectionViewDataSource,UICollectionViewDelegate	 {
    var songsList=[Any]()
    var audioPlayer: AVPlayer?
    var playerItem:AVPlayerItem?
    var currentPlayTime:TimeInterval?
    var timer = Timer()
    var imageCache : NSCache<AnyObject, UIImage> = NSCache()
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var songsCollectionView: UICollectionView!
    
    @IBOutlet weak var playerLayoutView: UIView!
    @IBOutlet weak var songNameLabel: UILabel!
    @IBOutlet weak var progressIndicator: UISlider!
    @IBOutlet weak var songDurationLabel: UILabel!
    @IBOutlet weak var currentTimeLabel: UILabel!
    var songImage:UIImage!
    // MARK: VC Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        updateViewTheme(themeStyle: appDelegate.ApplicationThemeStyleDefault)
        
        songsCollectionView.dataSource=self
        songsCollectionView.delegate=self
        songsCollectionView.decelerationRate=UIScrollViewDecelerationRateFast
        let nib = UINib(nibName: "SongInfoCell", bundle: nil)
        songsCollectionView.register(nib, forCellWithReuseIdentifier: "songInfoCell")
        var jsonResponse:Any?
        if let path = Bundle.main.path(forResource: "songs", ofType: "json") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                 jsonResponse = try JSONSerialization.jsonObject(with: data, options: .mutableLeaves)
                
            } catch {
                // handle error
                print("Error deserializing JSON: \(error)")
            }
            songsList=(jsonResponse as? [Any])!
        }
        do {
            let url = URL(string: "https://soundcloud.com/edsheeran/shape-of-you")
            playerItem = AVPlayerItem(url: url!)
            audioPlayer = AVPlayer(playerItem: playerItem)
            let currentItemDurationAsCMTime:CMTime = (audioPlayer?.currentItem?.asset.duration)!
            if(!(currentItemDurationAsCMTime.seconds.isNaN||currentItemDurationAsCMTime.seconds.isInfinite)){
                songDurationLabel.text = changeTimeIntervalToDisplayableString(time: currentItemDurationAsCMTime.seconds)
                progressIndicator.minimumValue=0.0
                progressIndicator.maximumValue=Float(currentItemDurationAsCMTime.seconds)
                
            }
            if let metadataList = playerItem?.asset.metadata{
                for item in metadataList {
                    if item.commonKey != nil && item.value != nil {
                        if item.commonKey  == "title" {
                            print("title:\(item.stringValue!)")
                            songNameLabel.text = item.stringValue!
                            songNameLabel.translatesAutoresizingMaskIntoConstraints = false
                            setupAutoLayout(label: songNameLabel)
                            if(songNameLabel.isTruncated()){
                                startMarqueeLabelAnimation(label: songNameLabel)
                            }
                        }
                        if item.commonKey   == "type" {
                            print("type:\(item.stringValue!)")
                            //nowPlayingInfo[MPMediaItemPropertyGenre] = item.stringValue
                        }
                        if item.commonKey  == "albumName" {
                            print("albumName:\(item.stringValue!)")
                            //nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = item.stringValue
                        }
                        if item.commonKey   == "artist" {
                            print("artist:\(item.stringValue!)")
                            artistLabel.text = item.stringValue
                        }
                        if item.commonKey  == "artwork" {
                            if let image = UIImage(data: (item.value as! NSData) as Data) {
                                //nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: image)
                                print("imageDesc:\(image.description)")
                               
                                songImage = image
                            }
                        }
                    }
                }
                
            }

        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.finishedPlaying(myNotification:)),
            name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
            object: audioPlayer?.currentItem)
    }
    override func viewWillDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self)
    }
    // MARK: CollectionView Methods
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return songsList.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let reuseIdentifier = "songInfoCell"
        let cell:SongInfoCell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath as IndexPath) as! SongInfoCell
        cell.songThumbnailImage.image=UIImage(named: "musicSymbolsImage.png")
        let imageUrlString = (songsList[indexPath.row] as! [String:String])["imageUrl"]
        let url = URL(string: imageUrlString!)!
        if let cachedVersionImage = imageCache.object(forKey: url as AnyObject) {
            // use the cached version
            cell.songThumbnailImage.image=cachedVersionImage
        } else {
            // create it from scratch then store in the cache
            getDataFromUrl(url:url) { data, response, error in
                guard let data = data, error == nil else { return }
                DispatchQueue.main.async() {
                    if let updateCell:SongInfoCell = collectionView.cellForItem(at: indexPath) as? SongInfoCell{
                        updateCell.songThumbnailImage.image=UIImage(data: data)
                        self.imageCache.setObject(UIImage(data:data)!, forKey: url as AnyObject)
                    }
                }
        }
        
        }
        
        return cell;
        
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        highLightCellAtIndexPath(indexPath: indexPath)
    }
    
    func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        return CGSize(width: collectionView.frame.size.width, height: collectionView.frame.size.width+40)
    }
    func scrollToNearestVisibleCollectionViewCell() {
        let visibleCenterPositionOfScrollView = Float(songsCollectionView.contentOffset.x + (songsCollectionView!.bounds.size.width / 2))
        var closestCellIndex = -1
        var closestDistance: Float = .greatestFiniteMagnitude
        for i in 0..<songsCollectionView.visibleCells.count {
            let cell = songsCollectionView.visibleCells[i]
            let cellWidth = cell.bounds.size.width
            let cellCenter = Float(cell.frame.origin.x + cellWidth / 2)
            
            // Now calculate closest cell
            let distance: Float = fabsf(visibleCenterPositionOfScrollView - cellCenter)
            if distance < closestDistance {
                closestDistance = distance
                closestCellIndex = songsCollectionView.indexPath(for: cell)!.row
            }
        }
        if closestCellIndex != -1 {
            highLightCellAtIndexPath(indexPath: IndexPath(row: closestCellIndex, section: 0))
        }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollToNearestVisibleCollectionViewCell()
        
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            scrollToNearestVisibleCollectionViewCell()
        }
    }
    func highLightCellAtIndexPath(indexPath:IndexPath){
        songsCollectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        for i in 0..<songsCollectionView.visibleCells.count {
            let cell = songsCollectionView.visibleCells[i]
            cell.layer.borderWidth=0.0
            cell.alpha=0.3
        }
        let cell = songsCollectionView.cellForItem(at: indexPath)
        cell?.layer.borderWidth = 2.0
        cell?.layer.borderColor = UIColor.gray.cgColor
        cell?.layer.cornerRadius=(cell?.layer.frame.width)!/2
        cell?.alpha=1.0
    }
    // MARK: Outlet Methods
    @IBAction func playAudioAtSliderValue(_ sender: Any) {
        if audioPlayer?.rate == 0{
            audioPlayer?.seek(to: CMTimeMakeWithSeconds(Float64(progressIndicator.value), 1000))
            playButton.setImage(UIImage(named: "pauseIcon.png"), for: .normal)
            timer.invalidate()
            timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.updateCurrentTime), userInfo: nil, repeats: true)
        } else {
            audioPlayer?.seek(to: CMTimeMakeWithSeconds(Float64(progressIndicator.value), 1000))
        }
        
    }
    @IBAction func playButtonClick(_ sender: Any) {
        
        if audioPlayer?.rate == 0{
            audioPlayer!.play()
            playButton.setImage(UIImage(named: "pauseIcon.png"), for: .normal)
            timer.invalidate()
            timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.updateCurrentTime), userInfo: nil, repeats: true)
        } else {
            audioPlayer!.pause()
            playButton.setImage(UIImage(named: "playIcon.png"), for: .normal)
            timer.invalidate()
        }
    }
    // MARK: Helper Methods
    func updateViewTheme(themeStyle:String){
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        var vcBGColor:UIColor
        var vcTextColor:UIColor
        vcBGColor=appDelegate.defaultThemeBGColor
        vcTextColor=appDelegate.defaultThemeTextColor
        
        if(themeStyle==appDelegate.ApplicationThemeStyleDark){
            vcBGColor=appDelegate.darkThemeBGColor
            vcTextColor=appDelegate.darkThemeTextColor
        }
        else if(themeStyle==appDelegate.ApplicationThemeStyleDefault){
            vcBGColor=appDelegate.defaultThemeBGColor
            vcTextColor=appDelegate.defaultThemeTextColor
        }
        self.artistLabel.textColor=vcTextColor
        self.currentTimeLabel.textColor=vcTextColor
        self.songDurationLabel.textColor=vcTextColor
        self.songNameLabel.textColor=vcTextColor
        
        self.playerLayoutView.backgroundColor=vcBGColor
        self.songsCollectionView.backgroundColor=vcBGColor
        self.view.backgroundColor=vcBGColor
    }
    func updateCurrentTime(){
        let currentCMTime:CMTime=(audioPlayer?.currentTime())!
        let currentTime:TimeInterval=currentCMTime.seconds
        currentTimeLabel.text=changeTimeIntervalToDisplayableString(time: currentTime)
        progressIndicator.setValue(Float(currentTime), animated: false)
        print("loadedTimeRanges:\(String(describing: audioPlayer?.currentItem?.loadedTimeRanges))")
        print("seekableTimeRanges:\(String(describing: audioPlayer?.currentItem?.seekableTimeRanges))")
    }
    func changeTimeIntervalToDisplayableString(time:TimeInterval)->String{
        var minutes = floor(time/60)
        var seconds = Int(round(time - minutes * 60))
        if(seconds==60){
            seconds=0
            minutes=minutes+1
        }
        let stringMinutes:String
        let stringSeconds:String
        if(Int(minutes)<10){
            stringMinutes="0\(Int(minutes))"
        }
        else{
            stringMinutes="\(Int(minutes))"
        }
        if(seconds<10){
            stringSeconds="0\(seconds)"
        }
        else{
            stringSeconds="\(seconds)"
        }
        return "\(stringMinutes):\(stringSeconds)"
    }
    func startMarqueeLabelAnimation(label:UILabel) {
        
        DispatchQueue.main.async(execute: {
            
            UILabel.animate(withDuration: 10.0, delay: 0.0, options: ([.curveEaseOut, .repeat]), animations: {() -> Void in
                label.frame.origin.x-=200
                
            }, completion:  nil)
        })
    }
    func setupAutoLayout(label:UILabel) {
        let horizontalConstraintLeft = NSLayoutConstraint(item: label, attribute: NSLayoutAttribute.leftMargin, relatedBy: NSLayoutRelation.equal, toItem: playerLayoutView, attribute: NSLayoutAttribute.leftMargin, multiplier: 1, constant: 20)
        let horizontalConstraintRight = NSLayoutConstraint(item: label, attribute: NSLayoutAttribute.rightMargin, relatedBy: NSLayoutRelation.equal, toItem: playerLayoutView, attribute: NSLayoutAttribute.rightMargin, multiplier: 1, constant: 20)
        let verticalConstraint = NSLayoutConstraint(item: label, attribute: NSLayoutAttribute.topMargin, relatedBy: NSLayoutRelation.equal, toItem: playerLayoutView, attribute: NSLayoutAttribute.topMargin, multiplier: 1, constant: 20)
        
        self.playerLayoutView.addConstraints([horizontalConstraintLeft,horizontalConstraintRight, verticalConstraint])
        
    }
    func finishedPlaying(myNotification:Notification) {
        playButton.setImage(UIImage(named: "playIcon.png"), for: .normal)
        timer.invalidate()
        let stopedPlayerItem: AVPlayerItem = myNotification.object as! AVPlayerItem
        stopedPlayerItem.seek(to:kCMTimeZero)
        currentTimeLabel.text=changeTimeIntervalToDisplayableString(time: kCMTimeZero.seconds)
        progressIndicator.setValue(Float(kCMTimeZero.seconds), animated: false)
    }
    func getDataFromUrl(url: URL, completion: @escaping (Data?, URLResponse?, Error?) -> ()) {
        URLSession.shared.dataTask(with: url) { data, response, error in
            completion(data, response, error)
            }.resume()
    }
}
