//
//  RavePayWebViewController.swift
//  GetBarter
//
//  Created by Olusegun Solaja on 15/08/2018.
//  Copyright © 2018 Olusegun Solaja. All rights reserved.
//

import UIKit
import WebKit
import RxSwift
protocol  FlutterwavePayWebProtocol : class{
    func tranasctionSuccessful(flwRef:String,responseData:FlutterwaveDataResponse?)
    
}

class RavePayWebViewController: UIViewController, WKNavigationDelegate,WKUIDelegate {
    var webView: WKWebView!
    var url:String?
    var flwRef:String?
    var progressView: UIProgressView!
    let diposableBag = DisposeBag()
    weak var delegate:FlutterwavePayWebProtocol?
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let _URL = url{
            let ur = _URL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            if let _d = ur{
                let _url = URL(string: _d)
                if let theURL = _url {
                    let request = URLRequest(url: theURL)
                    webView.load(request)
                    webView.allowsBackForwardNavigationGestures = true
                }
            }
        }
        progressView = UIProgressView(progressViewStyle: .default)
        progressView.sizeToFit()
        progressView.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        progressView.tintColor = UIColor(hex: "#F5A623")
        navigationController?.navigationBar.addSubview(progressView)
        let navigationBarBounds = self.navigationController?.navigationBar.bounds
        progressView.frame = CGRect(x: 0, y: navigationBarBounds!.size.height - 2, width: navigationBarBounds!.size.width, height: 2)
        
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        setUpObservers()
    }
    
    func setUpObservers(){
        PaymentServicesViewModel.sharedViewModel.mpesaVerifyResponse.observeOn(MainScheduler.instance).subscribe(onNext: {response in
            if(response.getStatus() != PaymentState.PENDING){
                self.delegate?.tranasctionSuccessful(flwRef: response.data?.flwRef ?? "", responseData: response.data?.toFlutterResponse())
                self.progressView.removeFromSuperview()
                self.navigationController?.popViewController(animated: true)
            }
            
        } ).disposed(by: diposableBag)
        
        PaymentServicesViewModel.sharedViewModel.error.observeOn(MainScheduler.instance).subscribe(onNext: { error in
            self.progressView.removeFromSuperview()
            showSnackBarWithMessage(msg: error )
            
        } ).disposed(by: diposableBag)
    }
    
    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        var scriptContent = "var meta = document.createElement('meta');"
        scriptContent += "meta.name='viewport';"
        scriptContent += "meta.content='width=device-width';"
        scriptContent += "document.getElementsByTagName('head')[0].appendChild(meta);"
        webView.evaluateJavaScript(scriptContent, completionHandler: nil)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.navigationDelegate = self
        self.view = webView
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            progressView.progress = Float(webView.estimatedProgress)
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("doneLoading")
            self.navigationItem.title = webView.title
            print(webView.url!.absoluteString)
            if (webView.url!.absoluteString.contains("/complete") ||
                webView.url!.absoluteString.contains("submitting_mock_form")){
                print("success page")
                PaymentServicesViewModel.sharedViewModel.mpesaVerify(flwRef: flwRef!)
                
            }else if(webView.url!.absoluteString.contains("/finish")){
                let newURL = webView.url!.absoluteString
                if let range = newURL.range(of: "https://webhook.site/finish") {
                    let dataPayload = newURL[range.upperBound...]
                    print("Extra Data \(dataPayload)")
                }
                let data = webView.url!.queryParameters
                let response = data?["resp"] as? String
                
                do{
                    let products = try JSONDecoder().decode(MobileMoneyUrlResponse.self, from: response?.data(using: .utf8) ?? Data())
                    
                    PaymentServicesViewModel.sharedViewModel.mpesaVerify(flwRef: products.data.flwRef ?? "")
                    
                 
                
                } catch(let error) {
                    print("\(error.localizedDescription)")
                           }
    //            print("Extra PayData \(products)")
                
            }
            
        }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    
    
}

extension URL {
    public var queryParameters: [String: String]? {
        guard
            let components = URLComponents(url: self, resolvingAgainstBaseURL: true),
            let queryItems = components.queryItems else { return nil }
        return queryItems.reduce(into: [String: String]()) { (result, item) in
            print("Query Term \(item.name)")
            result[item.name] = item.value
        }
    }
}



