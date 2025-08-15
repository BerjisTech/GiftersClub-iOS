//
//  RaveMpesaClient.swift
//  GetBarter
//
//  Created by Olusegun Solaja on 14/08/2018.
//  Copyright © 2018 Olusegun Solaja. All rights reserved.
//

import Foundation
import UIKit

class FlutterwaveMpesaClient {
    public var amount:String?
    public var phoneNumber:String?
    public var email:String? = ""
    typealias FeeSuccessHandler = ((String?,String?) -> Void)
    typealias PendingHandler = ((String?,String?) -> Void)
    typealias ErrorHandler = ((String?,FlutterwaveDataResponse?) -> Void)
    typealias SuccessHandler = ((String?,FlutterwaveDataResponse?) -> Void)
    public var error:ErrorHandler?
    public var feeSuccess:FeeSuccessHandler?
    public var transactionReference:String?
    public var chargeSuccess: SuccessHandler?
    public var chargePending: PendingHandler?
    public var businessNumber:String?
    public var accountNumber:String?
    
    //MARK: Transaction Fee
//    public func getFee(){
//        if let pubkey = FlutterwaveConfig.sharedConfig().publicKey{
//            
//            let param = [
//                "PBFPubKey": pubkey,
//                "amount": amount!,
//                "currency": FlutterwaveConfig.sharedConfig().currencyCode,
//                "ptype": "3"]
//            FlutterwavePayService.getFee(param, resultCallback: { (result) in
//                let data = result?["data"] as? [String:AnyObject]
//                if let _fee =  data?["fee"] as? Double{
//                    let fee = "\(_fee)"
//                    let chargeAmount = data?["charge_amount"] as? String
//                    self.feeSuccess?(fee,chargeAmount)
//                }else{
//                    if let err = result?["message"] as? String{
//                        self.error?(err,nil)
//                    }
//                }
//            }, errorCallback: { (err) in
//                
//                self.error?(err,nil)
//            })
//        }else{
//            self.error?("Public Key is not specified",nil)
//        }
//    }
    
    //MARK: Charge
    public func chargeMpesa(){
        if let pubkey = FlutterwaveConfig.sharedConfig().publicKey{
            var country :String = ""
            switch FlutterwaveConfig.sharedConfig().currencyCode {
            case "KES","TZS","GHS","ZAR":
                country = FlutterwaveConfig.sharedConfig().country
            default:
                country = "NG"
            }
            var param:[String:Any] = [
                "PBFPubKey": pubkey,
                "amount": amount!,
                "email": email!,
                "is_mpesa":"1",
                "is_mpesa_lipa":"1",
                "phonenumber":phoneNumber ?? "",
                "firstname":FlutterwaveConfig.sharedConfig().firstName ?? "",
                "lastname": FlutterwaveConfig.sharedConfig().lastName ?? "",
                "currency": FlutterwaveConfig.sharedConfig().currencyCode ,
                "payment_type": "mpesa",
                "country":country ,
                "meta":"",
                "IP": getIFAddresses().first!,
                "txRef": transactionReference!,
                "device_fingerprint": (UIDevice.current.identifierForVendor?.uuidString)!
            ]
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
          
            
            MobileMoneyViewModel.sharedViewModel.mpesaMoney(amount: amount!, phoneNumber: phoneNumber ?? "")
            
            
            
        }
    }
    

    
    
    
}
