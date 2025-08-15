//
//  VersionTwoApi.swift
//  RaveSDK
//
//  Created by Rotimi Joshua on 13/09/2020.
//

import Foundation

enum VersionTwoServicesApi{
    case saveCard
    case fetchCard
    case otpSavedCard
    case removeCard
    case getBank
    case chargeSavedCard
}


extension VersionTwoServicesApi:EndpointType{
    var stagingURL: URL {
         return URL(string: "https://rave-api-v2.herokuapp.com/")!
    }
   
    var baseURL: URL {
        return URL(string: "https://api.ravepay.co/")!
    }

    var path: String {
        switch self {
        case .saveCard:
            return "v2/gpx/devices/save"
        case .fetchCard:
            return "v2/gpx/users/lookup"
        case .removeCard:
            return "v2/gpx/users/remove"
        case .otpSavedCard:
            return "v2/gpx/users/send_otp"
        case .getBank:
            return "flwv3-pug/getpaidx/api/flwpbf-banks.js?json=1"
        case .chargeSavedCard:
            return "flwv3-pug/getpaidx/api/charge"
        }
 
       
    }
}
