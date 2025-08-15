//
//  Version3Services.swift
//  RaveSDK
//
//  Created by Rotimi Joshua on 26/08/2020.
//


import Foundation

enum VersionThreeServicesApi{
    case chargeCard
    case validateCard
    case mpesaVerify
    case pwbtVerify
    case mpesa
    case nigeriaBankAccount
    case bankTransfer
    case ukAccountPayment
    case ussd
    case ghanaMoney
    case rwandaMoney
    case ugandaMoney
    case zambiaMoney
    case francophoneMoney
    case nigeriaBankTransfer
    case voucherCharge
}

enum MonitorAPIService {
    case monitor
}


extension MonitorAPIService:EndpointType{
    var baseURL: URL {
        return URL(string: "https://kgelfdz7mf.execute-api.us-east-1.amazonaws.com/staging/")!
    }
    
    var stagingURL: URL {
        return URL(string: "https://kgelfdz7mf.execute-api.us-east-1.amazonaws.com/staging/")!
    }
    
    var path: String {
        switch self {
        case .monitor:
         return   "sendevent"
        }
    }
    
    
}


extension VersionThreeServicesApi:EndpointType{
    var stagingURL: URL {
        return URL(string: "https://ravesandboxapi.flutterwave.com/v3/sdkcheckout/")!
    }
    
    var baseURL: URL {
       return URL(string: "https://api.ravepay.co/v3/sdkcheckout/")!
    }
    

    var path: String {
        switch self {
        case .chargeCard:
            return "charges?type=card"
        case .validateCard:
            return "validate-charge"
        case .mpesaVerify:
            return "mpesa-verify"
        case .pwbtVerify:
            return "pwbt-verify"
        case .mpesa:
            return "charges?type=mpesa"
        case .nigeriaBankAccount:
            return "charges?type=debit_ng_account"
        case .bankTransfer:
            return "charges?type=bank_transfer"
        case .ukAccountPayment:
            return "charges?type=debit_uk_account"
        case .ussd:
            return "charges?type=ussd"
        case .ghanaMoney:
            return "charges?type=mobile_money_ghana"
        case .rwandaMoney:
            return "charges?type=mobile_money_rwanda"
        case .ugandaMoney:
            return "charges?type=mobile_money_uganda"
        case .zambiaMoney:
            return "charges?type=mobile_money_zambia"
        case .francophoneMoney:
            return "charges?type=mobile_money_franco"
        case .nigeriaBankTransfer:
            return "charges?type=bank_transfer"
        case .voucherCharge:
            return "charges?type=voucher_payment"
        }
 
       
    }
 
}




