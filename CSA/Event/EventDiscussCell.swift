//
//  EventDiscussCell.swift
//  Duke CSA
//
//  Created by Zhe Wang on 4/16/15.
//  Copyright (c) 2015 Zhe Wang. All rights reserved.
//

import UIKit

class EventDiscussCell: UITableViewCell, UITextViewDelegate{
    
    @IBOutlet weak var lblUser: UserLabel!
    @IBOutlet weak var imgPropic: UIImageView!
    @IBOutlet weak var lblMainPost: UILabel!
    @IBOutlet weak var lblPostTime: UILabel!
    @IBOutlet weak var btnDelete: UIButton!
    @IBOutlet weak var imgCommentBubble: UIImageView!
    
    let timeoutInSec:NSTimeInterval = 5.0
    
    weak var parentVC:EventDiscussViewController! //must be weak to avoid strong reference cycle
    var childDis:Discussion!
    
    var postConnectSuccess = false
    var postAllowed = true
    
    @IBAction func onDeleteDicussion(sender: AnyObject) {
        
        let str = "Delete this discussion?"
        let alert = UIAlertController(title: nil, message: str, preferredStyle: UIAlertControllerStyle.Alert)
        let defaultAction = UIAlertAction(title: "Delete", style: UIAlertActionStyle.Default) { _ in
            self.childDis.PFInstance[PFKey.IS_VALID] = false
            self.childDis.PFInstance.saveInBackground()
            if let i = self.parentVC.discussions.indexOf(self.childDis){
                self.parentVC.discussions.removeAtIndex(i)
                self.parentVC.tableView.reloadData()
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel, handler:nil) 
        alert.addAction(defaultAction)
        alert.addAction(cancelAction)
        parentVC.presentViewController(alert, animated: true, completion: nil)
    }
    
    
    @IBAction func onClickReply(sender: AnyObject) {
        parentVC.kbInput.txtview.delegate = self
        parentVC.replyPressed(scrollTo: self.frame.maxY)
    }
    
    @IBAction func onClickLike(sender: AnyObject) {
        if childDis.IdidLike {
            childDis.PFInstance.removeObject(PFUser.currentUser()!, forKey: PFKey.EVENT.DIS.LIKES)
            childDis.PFInstance.saveInBackground()
            let id = PFUser.currentUser()!.objectId
            for (i, u) in childDis.likes.enumerate() {
                if u.objectId == id {
                    childDis.likes.removeAtIndex(i)
                }
            }
            childDis.IdidLike = false
        }else{
            childDis.PFInstance.addObject(PFUser.currentUser()!, forKey: PFKey.EVENT.DIS.LIKES)
            let message = "\(PFUser.currentUser()![PFKey.USER.DISPLAY_NAME] as! String) likes your discussion about the event '\(childDis.parent[PFKey.EVENT.TITLE] as! String).'"
            let sendToUser = childDis.author
            childDis.PFInstance.saveInBackgroundWithBlock({ (success:Bool, error:NSError?) -> Void in
                if success {
                    //push notif
                    AppNotif.pushNotification(forType: AppNotif.NotifType.NEW_RS_LIKE, withMessage: message, toUser: sendToUser, withSoundName: AppConstants.SoundFile.NOTIF_1)
                }
            })
            childDis.likes.append(PFUser.currentUser()!)
            childDis.IdidLike = true
        }
        parentVC.tableView.reloadData()
    }
    //called everytime textview's text is changed. Used here to detect return (send) pressed.
    func textView(textView: UITextView, shouldChangeTextInRange range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            onPostReply(textView.text)
            textView.resignFirstResponder()
            return false
        }
        return true
    }
    
    
    func onPostReply(txt:String) {
        if !postAllowed{
            return
        }
        //check string
        if !AppTools.stringIsValid(txt) {return}
        
        //create new parse object
        let newPFReply = PFObject(className: PFKey.EVENT.DIS.RE.CLASSKEY)
        newPFReply[PFKey.IS_VALID] = true
        newPFReply[PFKey.EVENT.DIS.RE.PARENT] = childDis.PFInstance
        newPFReply[PFKey.EVENT.DIS.RE.AUTHOR] = PFUser.currentUser()!
        newPFReply[PFKey.EVENT.DIS.RE.MAIN_POST] = txt
        childDis.PFInstance.addObject(newPFReply, forKey: PFKey.EVENT.DIS.REPLIES)
        
        //change app status
        postConnectSuccess = false
        postAllowed = false
        parentVC.view.makeToastActivity(position: HRToastPositionCenterAbove, message: "Posting...")
        AppFunc.pauseApp()
        
        //set time out timer
        NSTimer.scheduledTimerWithTimeInterval(timeoutInSec, target: self, selector: Selector("postTimeOut"), userInfo: nil, repeats: false)
        
        let message = "\(PFUser.currentUser()![PFKey.USER.DISPLAY_NAME] as! String) replied to your discussion about the event '\(childDis.parent[PFKey.EVENT.TITLE] as! String)'."
        let sendToUser = childDis.author
        
        //parse backend
        childDis.PFInstance.saveInBackgroundWithBlock { (success:Bool, error:NSError?) -> Void in
            //change app status
            self.postConnectSuccess = true
            self.postAllowed = true
            AppFunc.resumeApp()
            self.parentVC.view.hideToastActivity()
            
            //case handle
            if success{
                self.parentVC.kbInput.txtview.text = ""
                //append to discussion's replies array
                let newRep = Reply(parseObject: newPFReply, parentDis: self.childDis)!
                self.childDis.replies.append(newRep)
                self.parentVC.view.makeToast(message: "Succeeded.", duration: 0.5, position: HRToastPositionCenterAbove)
                self.parentVC.tableView.reloadData()
                AppNotif.pushNotification(forType: AppNotif.NotifType.NEW_EDIS_REPLY, withMessage: message, toUser: sendToUser, withSoundName: AppConstants.SoundFile.NOTIF_1)
            }else{
                self.parentVC.view.makeToast(message: "Failed to comment. Please check your internet connection.", duration: 1.5, position: HRToastPositionCenterAbove)
            }
        }
    }
    
    func postTimeOut() {
        if !postConnectSuccess{
            AppFunc.resumeApp()
            postAllowed = true
            self.parentVC.view.hideToastActivity()
            self.parentVC.view.makeToast(message: "Connecting time out, job sended into background. Please wait.", duration: 1.5, position: HRToastPositionCenterAbove)
        }
    }
    
    func initWithDiscussion(dis:Discussion, fromVC:EventDiscussViewController, fromTableView tableView:UITableView, forIndexPath indexPath:NSIndexPath) {
        childDis = dis
        parentVC = fromVC
        AppFunc.downloadPropicFromParse(user: childDis.author, saveToImgView: imgPropic, inTableView: tableView, forIndexPath: indexPath)
        lblUser.initLabel(author: childDis.author, fontSize: 15, fromVC: parentVC)
        lblMainPost.text = childDis.mainPost
        lblPostTime.text = AppTools.formatDateUserFriendly(childDis.postTime)
        if childDis.author.objectId == PFUser.currentUser()!.objectId {
            self.btnDelete.hidden = false
        }else{
            self.btnDelete.hidden = true
        }
        layoutIfNeeded()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        imgPropic.layer.cornerRadius = 20.0
        imgPropic.layer.masksToBounds = true
        btnDelete.hidden = true
    }
}
