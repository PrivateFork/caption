//
//  ViewController.swift
//  caption
//
//  Created by Wouter van de Kamp on 25/03/2017.
//  Copyright © 2017 Wouter van de Kamp. All rights reserved.
//

import Cocoa
import Gzip

class ViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    @IBOutlet weak var subtitleTableView: NSTableView!
    @IBOutlet weak var searchField: NSTextField!
    @IBOutlet weak var languagePopUp: NSPopUpButton!
    @IBOutlet weak var searchLoadingIndicator: NSProgressIndicator!
    @IBOutlet weak var searchEraseButton: NSButton!
    
    
    private var selectedLanguage:String!
    private var searchData = [SubtitleSearchDataModel]()
    typealias FinishedLogIn = () -> ()
    
    override func viewDidLoad() {
        self.searchLoadingIndicator.isHidden = true
        self.searchEraseButton.isHidden = true
        
        initCustomSearchField()
        initNSPopUpButton()
        
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    
    
    // MARK: - TextField (Should move this to the subclass, but doesn't work 100% yet.) 
    // See http://stackoverflow.com/questions/43292681/nstextfield-fades-out-after-subclassing
    // for more information
    func initCustomSearchField() {
        searchField.wantsLayer = true
        let textFieldLayer = CALayer()
        searchField.layer = textFieldLayer
        searchField.backgroundColor = NSColor.white
        searchField.layer?.backgroundColor = CGColor.white
        searchField.layer?.borderColor = CGColor.white
        searchField.layer?.borderWidth = 0
        searchField.delegate = self
    }
    
    @IBAction func searchSubtitles(_ sender: NSTextField) {
        let searchTerm = searchField.stringValue
        searchData.removeAll()
        subtitleTableView.reloadData()
        searchLoadingIndicator.isHidden = false
        searchLoadingIndicator.startAnimation(NSTextField.self)
        osSearch(selectedLan: selectedLanguage, query: searchTerm)
    }
    
    override func controlTextDidChange(_ obj: Notification) {
        if searchField.stringValue != "" {
            searchEraseButton.isHidden = false
        } else {
            searchEraseButton.isHidden = true
        }
    }
    
    @IBAction func didClickErase(_ sender: NSButton) {
        searchField.stringValue = ""
        searchEraseButton.isHidden = true
    }
    
    // MARK: - Dropdown List
    private func initNSPopUpButton() {
        selectedLanguage = "eng"
        languagePopUp.removeAllItems()
        languagePopUp.addItems(withTitles: (LanguageList.languageDict.allKeys as! [String]).sorted())
        languagePopUp.selectItem(withTitle: "English")
    }
    
    @IBAction func didSelectLanguage(_ sender: NSPopUpButton) {
        self.selectedLanguage = LanguageList.languageDict.object(forKey: languagePopUp.titleOfSelectedItem! as String)! as! String
    }
    
    
    // MARK: - Tableview
    func numberOfRows(in tableView: NSTableView) -> Int {
        return searchData.count
    }
    
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellView = tableView.make(withIdentifier: "cell", owner: self) as! NSTableCellView
        if searchData[row].MovieReleaseName != nil {
            cellView.textField?.stringValue = searchData[row].MovieReleaseName!
        } else {
            cellView.textField?.stringValue = "Title is missing"
        }
        return cellView
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return SubtitleTableViewRow()
    }
    
    func osLogin(completed: @escaping FinishedLogIn) {
        let params = ["", "", "en", OpenSubtitleConfiguration.userAgent] as [Any]
        
        let loginManager = OpenSubtitleDataManager(
            secureBaseURL: OpenSubtitleConfiguration.secureBaseURL!,
            osMethod: "LogIn",
            parameters: params)
        
        loginManager.fetchOpenSubtitleData { (response) in
            OpenSubtitleConfiguration.token = response[0]["token"].string!
            completed()
        }
    }
    
    
    @IBAction func didSelectRow(_ sender: NSTableView) {
        if searchData.count != 0 {
            let selectedRow = subtitleTableView.selectedRow
            let subtitleID = searchData[selectedRow].IDSubtitleFile
            let movieName = searchData[selectedRow].MovieReleaseName
            osDownload(subtitleID: subtitleID!, movieName: movieName!)
        }
    }
    
    
    func osSearch(selectedLan: String!, query: String?) {
        osLogin { () -> () in
            self.searchData = [SubtitleSearchDataModel]()
            let params = [OpenSubtitleConfiguration.token!, [["sublanguageid": selectedLan!, "query": query!]]] as [Any]
            
            let searchManager = OpenSubtitleDataManager(
                secureBaseURL: OpenSubtitleConfiguration.secureBaseURL!,
                osMethod: "SearchSubtitles",
                parameters: params)
            
            searchManager.fetchOpenSubtitleData { (response) in
                let data = response[0]["data"].array
                if data == nil {
                    print("No Results")
                } else {
                    for subtitle in data! {
                        let subtitleData = SubtitleSearchDataModel(subtitle: subtitle)
                        self.searchData.append(subtitleData!)
                    }
                    
                    DispatchQueue.main.async {
                        self.searchLoadingIndicator.isHidden = true
                        self.searchLoadingIndicator.stopAnimation(response)
                        self.subtitleTableView.reloadData()
                    }
                }
            }
        }
    }
    
    func osDownload(subtitleID: String, movieName: String) {
        osLogin { () -> () in
            let params = [OpenSubtitleConfiguration.token!, [subtitleID]] as [Any]
            
            let downloadManager = OpenSubtitleDataManager(
                secureBaseURL: OpenSubtitleConfiguration.secureBaseURL!,
                osMethod: "DownloadSubtitles",
                parameters: params)
            
            downloadManager.fetchOpenSubtitleData(completion: { (response) in
                let data = response[0]["data"].array
                if data == nil {
                    print("Download Unavailable")
                } else {
                    for download in data! {
                        let base64Str = download["data"].string!
                        let decodedData = Data(base64Encoded: base64Str)!
                        let decompressedData: Data
                        if decodedData.isGzipped {
                            decompressedData = try! decodedData.gunzipped()
                            DispatchQueue.main.async {
                                self.saveSubtitle(subtitle: decompressedData, filename: movieName)
                            }
                        } else {
                            decompressedData = decodedData
                        }
                    }
                }
            })
        }
    }
    
    func saveSubtitle(subtitle: Data, filename: String) {
        let fileContentToWrite = subtitle
        
        let FS = NSSavePanel()
        FS.canCreateDirectories = true
        FS.nameFieldStringValue = filename
        FS.title = "Save Subtitle"
        FS.allowedFileTypes = ["srt"]
        
        
        FS.beginSheetModal(for: self.view.window!, completionHandler: { result in
            if result == NSFileHandlingPanelOKButton {
                guard let url = FS.url else { return }
                do {
                    try fileContentToWrite.write(to: url)
                } catch {
                    print (error.localizedDescription)
                }
            }

        })
        
//        FS.begin { result in
//            if result == NSFileHandlingPanelOKButton {
//                guard let url = FS.url else { return }
//                do {
//                    try fileContentToWrite.write(to: url)
//                } catch {
//                    print (error.localizedDescription)
//                }
//            }
//        }
    }
}
