//
//  RaveConfig.swift
//  GetBarter
//
//  Created by Olusegun Solaja on 14/08/2018.
//  Copyright © 2018 Olusegun Solaja. All rights reserved.
//

import Foundation
public enum SuggestedAuthModel{
    case PIN,AVS_VBVSECURECODE,VBVSECURECODE,GTB_OTP,NOAUTH_INTERNATIONAL,NONE
}
public enum AuthModel{
    case OTP,WEB
}
public class FlutterwaveConfig {
    public var publicKey:String?
    public var encryptionKey:String?
    public var isStaging:Bool = true
    public var email:String?
    public var firstName:String?
    public var lastName:String?
    public var phoneNumber:String?
    public var transcationRef:String?
    public var duration:Double = 2
    public var frequency:Double = 5
    public var country:String = "NG"
    public var currencyCode:String = "NGN"
    public var narration:String?
    public var isPreAuth:Bool = false
    public var isPermanent:Bool = true
    public var meta:[[String:String]]?
    public var subAccounts:[SubAccount]?
    public var whiteListedBanksOnly:[String]?
    public var paymentOptionsToExclude:[PaymentOption] = []
    
    public class func sharedConfig() -> FlutterwaveConfig {
        struct Static {
            static let kbManager = FlutterwaveConfig()
            
        }
        return Static.kbManager
    }
}
