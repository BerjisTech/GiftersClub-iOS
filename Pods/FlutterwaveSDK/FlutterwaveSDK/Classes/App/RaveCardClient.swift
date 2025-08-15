//
//  RaveCardClient.swift
//  GetBarter
//
//  Created by Olusegun Solaja on 14/08/2018.
//  Copyright © 2018 Olusegun Solaja. All rights reserved.
//

import Foundation
import UIKit

class FlutterwaveCardClient{
    public var cardNumber:String?
    public var cardfirst6:String?
    public var cvv:String?
    public var amount:String?
    public var expYear:String?
    public var expMonth:String?
    public var saveCard = true
    public var otp:String?
    
    public var isSaveCardCharge:String?
    public var saveCardPayment:String?
    public var savedCardHash:String?
    public var savedCardMobileNumber:String?
    
    public var transactionReference:String?
    public var bodyParam:[String:Any]? = [:]
    
    typealias FeeSuccessHandler = ((String?,String?) -> Void)
    typealias SuccessHandler = ((String?,FlutterwaveDataResponse?) -> Void)
    typealias ErrorHandler = ((String?,FlutterwaveDataResponse?) -> Void)
    typealias SuggestedAuthHandler = ((SuggestedAuthModel,[String:Any]?, String?) -> Void)
    typealias OTPAuthHandler = ((String,String) -> Void)
    typealias WebAuthHandler = ((String,String) -> Void)
    typealias SaveCardSuccessHandler = (([SavedCard]?) -> Void)
    typealias SaveCardErrorHandler = ((String?) -> Void)
    typealias RemoveSavedCardSuccessHandler = (() -> Void)
    typealias RemoveSavedCardErrorHandler = ((String?) -> Void)
    
    public var error:ErrorHandler?
    public var saveCardError:SaveCardErrorHandler?
    public var saveCardSuccess:SaveCardSuccessHandler?
    public var removesavedCardError:RemoveSavedCardErrorHandler?
    public var removesavedCardSuccess:RemoveSavedCardSuccessHandler?
    public var validateError:ErrorHandler?
    public var feeSuccess:FeeSuccessHandler?
    public var chargeSuggestedAuth: SuggestedAuthHandler?
    public var chargeOTPAuth: OTPAuthHandler?
    public var chargeWebAuth: WebAuthHandler?
    public var chargeSuccess: SuccessHandler?
    public var sendOTPSuccess:SaveCardErrorHandler?
    public var sendOTPError:SaveCardErrorHandler?
    public var selectedCard:SavedCard?
    
    private var isRetryCharge = false
    private var retryChargeValue:String?
    
    
    
    //MARK: Charge Saved Card
    public func saveCardCharge(){
        if let pubkey = FlutterwaveConfig.sharedConfig().publicKey{
            var country :String = ""
            switch FlutterwaveConfig.sharedConfig().currencyCode {
            case "KES","TZS","GHS","ZAR":
                country = FlutterwaveConfig.sharedConfig().country
            default:
                country = "NG"
            }
            var param:[String:Any] = ["PBFPubKey":pubkey,
                                      "IP": getIFAddresses().first!,
                                      "device_fingerprint": (UIDevice.current.identifierForVendor?.uuidString)!,
                                      "email": FlutterwaveConfig.sharedConfig().email!,
                                      "currency": FlutterwaveConfig.sharedConfig().currencyCode,
                                      "country":country,
                                      "amount":amount ?? "",
                                      "firstname":FlutterwaveConfig.sharedConfig().firstName ?? "",
                                      "lastname": FlutterwaveConfig.sharedConfig().lastName ?? "",
                                      "txRef": FlutterwaveConfig.sharedConfig().transcationRef!]
            if let saveCard = isSaveCardCharge{
                param.merge(["is_saved_card_charge":saveCard])
            }
            if let _otp = otp{
                param.merge(["otp":_otp])
            }
            if let saveCardType = saveCardPayment{
                param.merge(["payment_type":saveCardType])
            }
            if let brand = selectedCard?.card?.cardBrand{
                if brand.lowercased() == "visa"{
                    param.merge(["is_visa":true])
                }else{
                    param.merge(["is_visa":false])
                }
                
            }
            if let device = selectedCard?.mobileNumber{
                param.merge(["device_key":device])
            }
            if let hash = selectedCard?.cardHash{
                param.merge(["card_hash":hash])
            }
            if FlutterwaveConfig.sharedConfig().isPreAuth{
                param.merge(["charge_type":"preauth"])
            }
            if let subAccounts = FlutterwaveConfig.sharedConfig().subAccounts{
                let subAccountDict =  subAccounts.map { (subAccount) -> [String:String] in
                    var dict = ["id":subAccount.id]
                    if let ratio = subAccount.ratio{
                        dict.merge(["transaction_split_ratio":"\(ratio)"])
                    }
                    if let chargeType = subAccount.charge_type{
                        switch chargeType{
                        case .flat :
                            dict.merge(["transaction_charge_type":"flat"])
                            if let charge = subAccount.charge{
                                dict.merge(["transaction_charge":"\(charge)"])
                            }
                        case .percentage:
                            dict.merge(["transaction_charge_type":"percentage"])
                            if let charge = subAccount.charge{
                                dict.merge(["transaction_charge":"\((charge / 100))"])
                            }
                        }
                    }
                    
                    return dict
                }
                param.merge(["subaccounts":subAccountDict])
            }
            if let meta = FlutterwaveConfig.sharedConfig().meta{
                param.merge(["meta":meta])
            }
            
            let jsonString  = param.jsonStringify()
            
            let secret = FlutterwaveConfig.sharedConfig().encryptionKey!
            let data =  TripleDES.encrypt(string: jsonString, key:secret)
            let base64String = data?.base64EncodedString()
            
            
            let reqbody = [
                "PBFPubKey": pubkey,
                "client": base64String!, // Encrypted $data payload here.
                "alg": "3DES-24"
            ]
            print("first-of-all")
            print(reqbody)
            CardViewModel.sharedViewModel.chargeSavedCard(client: base64String!)
//            FlutterwavePayService.charge(reqbody, resultCallback: { [weak self] (res) in
//                guard let strongSelf = self else {return}
//                if let status = res?["status"] as? String{
//                    if status == "success"{
//                        let result = res?["data"] as? Dictionary<String,AnyObject>
//                        let flwRef = result?["flwRef"] as? String?
//                        let authURL = result?["authurl"] as? String
//
//                        let flutterWaveData = FlutterwaveDataResponse(txRef: nil, flwRef:flwRef?.orEmpty(), deviceFingerprint: nil, amount: nil, chargedAmount: nil, appFee: nil, merchantFee: nil, processorResponse: nil, authModel: nil, currency: nil, ip: nil, narration: nil, status: nil, authURL: authURL, paymentType: nil, fraudStatus: nil, chargeType: nil, createdAt: nil, plan: nil, id: nil, accountID: nil, customer: nil, card: nil)
//                        if let suggestedAuth = result?["suggested_auth"] as? String{
//                            var authModel:SuggestedAuthModel = .NONE
//                            switch suggestedAuth {
//                            case "PIN":
//                                authModel = .PIN
//                            case "AVS_VBVSECURECODE":
//                                authModel = .AVS_VBVSECURECODE
//                            case "VBVSECURECODE":
//                                authModel = .VBVSECURECODE
//                            case "NOAUTH_INTERNATIONAL":
//                                authModel = .NOAUTH_INTERNATIONAL
//                            case "GTB_OTP":
//                                authModel = .GTB_OTP
//                            default:
//                                authModel = .NONE
//                            }
//
//                            strongSelf.chargeSuggestedAuth?(authModel,result!,authURL)
//
//                        }else{
//                            if let chargeResponse = result?["chargeResponseCode"] as? String{
//                                switch chargeResponse{
//                                case "00":
//                                    let flwTransactionRef = result?["flwRef"] as? String
//                                    strongSelf.chargeSuccess?(flwTransactionRef,flutterWaveData)
//                                case "02":
//                                    let flwTransactionRef = result?["flwRef"] as? String
//                                    var _instruction:String? =  result?["chargeResponseMessage"] as? String
//                                    if let instruction = result?["validateInstruction"] as? String{
//                                        _instruction = instruction
//                                    }else{
//                                        if let instruction = result?["validateInstructions"] as? [String:AnyObject]{
//                                            if let  _inst =  instruction["instruction"] as? String{
//                                                if _inst != ""{
//                                                    _instruction = _inst
//                                                }
//                                            }
//                                        }
//                                    }
//                                    if let authURL = result?["authurl"] as? String, authURL != "NO-URL", authURL != "N/A" {
//                                        // Show Web View
//                                        strongSelf.chargeWebAuth?(flwTransactionRef!,authURL)
//                                    }else{
//                                        if let flwRef = flwTransactionRef{
//                                            // Show OTP Screen
//                                            strongSelf.chargeOTPAuth?(flwRef, _instruction ?? "Pending OTP Validation")
//                                        }
//                                    }
//                                default:
//                                    break
//                                }
//                            }
//
//                        }
//                    }else{
//                        if let message = res?["message"] as? String{
//                            strongSelf.error?(message,nil)
//                        }
//                    }
//                }
//            }) {[weak self] (err) in
//                guard let strongSelf = self else {return}
//                strongSelf.error?(err,nil)
//            }
        }
    }
    //MARK: Charge Card
    public func chargeCard(replaceData:Bool = false){
        if let pubkey = FlutterwaveConfig.sharedConfig().publicKey{
            var country :String = ""
            switch FlutterwaveConfig.sharedConfig().currencyCode {
            case "KES","TZS","GHS","ZAR":
                country = FlutterwaveConfig.sharedConfig().country
            default:
                country = "NG"
            }
            guard let _ = cardNumber else {
                fatalError("Card Number is missing")
            }
            guard let _ = cvv else {
                fatalError("CVV Number is missing")
            }
            guard let _ = amount else {
                fatalError("Amount is missing")
            }
            guard let _ = expYear else {
                fatalError("Expiry Year is missing")
            }
            guard let _ = expMonth else {
                fatalError("Expiry Month is missing")
            }
            guard let _ = FlutterwaveConfig.sharedConfig().email else {
                fatalError("Email address is missing")
            }
            guard let _ = FlutterwaveConfig.sharedConfig().transcationRef else {
                fatalError("transactionRef is missing")
            }
            //            print("FUNCTION CARD \(cardNumber.orEmpty())")
            var param:[String:Any] = ["PBFPubKey":pubkey ,
                                      "card_number":cardNumber ?? "",
                                      "cvv":cvv ?? "",
                                      "amount":amount ?? "",
                                      "expiry_year":expYear ?? "",
                                      "expiry_month": expMonth ?? "",
                                      "preauthorize":FlutterwaveConfig.sharedConfig().isPreAuth,
                                      "fullname": "\(FlutterwaveConfig.sharedConfig().firstName.orEmpty()) \(FlutterwaveConfig.sharedConfig().lastName.orEmpty())",
                "email": FlutterwaveConfig.sharedConfig().email!,
                "currency": FlutterwaveConfig.sharedConfig().currencyCode,
                "country":country,
                //                                      "IP": getIFAddresses().first!,
                "tx_ref": FlutterwaveConfig.sharedConfig().transcationRef!,
                "device_fingerprint": (UIDevice.current.identifierForVendor?.uuidString)!]
            if let narrate = FlutterwaveConfig.sharedConfig().narration{
                param.merge(["narration":narrate])
            }
           
            
            if let subAccounts = FlutterwaveConfig.sharedConfig().subAccounts{
                let subAccountDict =  subAccounts.map { (subAccount) -> [String:String] in
                    var dict = ["id":subAccount.id]
                    if let ratio = subAccount.ratio{
                        dict.merge(["transaction_split_ratio":"\(ratio)"])
                    }
                    if let chargeType = subAccount.charge_type{
                        switch chargeType{
                        case .flat :
                            dict.merge(["transaction_charge_type":"flat"])
                            if let charge = subAccount.charge{
                                dict.merge(["transaction_charge":"\(charge)"])
                            }
                        case .percentage:
                            dict.merge(["transaction_charge_type":"percentage"])
                            if let charge = subAccount.charge{
                                dict.merge(["transaction_charge":"\((charge / 100))"])
                            }
                        }
                    }
                    
                    return dict
                }
                param.merge(["subaccounts":subAccountDict])
            }
            
            if let meta = FlutterwaveConfig.sharedConfig().meta{
                param.merge(["meta":meta])
            }
            if saveCard {
                if let phone = FlutterwaveConfig.sharedConfig().phoneNumber, phone != ""{
                    param.merge(["remember_device_mobile_key": phone, "remember_device_email":FlutterwaveConfig.sharedConfig().email!, "is_remembered":"1"])
                }
            }
           
            
            if replaceData {
                bodyParam = param
            }
            if isRetryCharge{
                if let retryValue = self.retryChargeValue{
                    bodyParam?.merge(["retry_charge":retryValue])
                }
            }
            let jsonString  = bodyParam!.jsonStringify()
            //            print("JSON SENT \(jsonString)")
            let secret = FlutterwaveConfig.sharedConfig().encryptionKey!
            let data =  TripleDES.encrypt(string: jsonString, key:secret)
            let base64String = data?.base64EncodedString()
            
            CardViewModel.sharedViewModel.saveCard = saveCard
            PaymentServicesViewModel.sharedViewModel.chargeCard(client: base64String!)
            
        }else{
            self.error?("Public Key is not specified",nil)
        }
    }
    
    //MARK: Validate Card
    public func validateCardOTP(){
        guard let ref = self.transactionReference, let _otp = otp else {
            self.error?("Transaction Reference  or OTP is not set",nil)
            return
        }
        
        PaymentServicesViewModel.sharedViewModel.validateCharge(otp: _otp, flwRef: ref, type: "card")
        
    }
    
    //MARK: Fetch saved card
//    func fetchSavedCards(){
//        if let pubkey = FlutterwaveConfig.sharedConfig().publicKey{
//            if let deviceNumber = FlutterwaveConfig.sharedConfig().phoneNumber {
//                let param = ["public_key":pubkey, "device_key":deviceNumber]
//                
//                FlutterwavePayService.getSavedCards(param, resultCallback: {[weak self] (cardResponse) in
//                    guard let  strongSelf = self else{ return}
//                    strongSelf.saveCardSuccess?(cardResponse.cards)
//                })  {[weak self] (err) in
//                    guard let  strongSelf = self else{ return}
//                    strongSelf.saveCardError?(err)
//                }
//            }
//            
//        }
//    }
    //MARK: Transaction Fee
//    public func removeSavedCard(){
//        if let pubkey = FlutterwaveConfig.sharedConfig().publicKey{
//            let param = [
//                "public_key": pubkey,
//                "card_hash": savedCardHash!,
//                "mobile_number": savedCardMobileNumber!]
//            FlutterwavePayService.removeSavedCard(param, resultCallback: {[weak self] (result) in
//                guard let strongSelf = self else {return}
//                strongSelf.removesavedCardSuccess?()
//                }, errorCallback: {[weak self] (err) in
//                    guard let strongSelf = self else {return}
//                    strongSelf.removesavedCardError?(err)
//            })
//        }else{
//            self.removesavedCardError?("Public Key is not specified")
//        }
//    }
    
    //MARK: Send OTP
//    func sendOTP(card: SavedCard){
//        if let pubkey = FlutterwaveConfig.sharedConfig().publicKey{
//            let param = ["public_key":pubkey,"card_hash":card.cardHash ?? "","device_key":card.mobileNumber ?? ""]
//            FlutterwavePayService.sendOTP(param, resultCallback: {[weak self] (message) in
//                guard let  strongSelf = self else{ return}
//                strongSelf.sendOTPSuccess?(message)
//            }) {[weak self] (err) in
//                guard let  strongSelf = self else{ return}
//                strongSelf.sendOTPError?(err)
//            }
//        }
//    }
    
    func isMasterCard() -> Bool{
        if let cardNumber = self.cardNumber{
            if cardNumber.hasPrefix("5"){
                return true
            }else{
                return false
            }
        }else{
            return false
        }
    }
    
    
    
}
