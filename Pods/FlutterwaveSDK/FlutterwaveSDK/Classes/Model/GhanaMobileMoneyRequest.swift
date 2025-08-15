//
//  GhanaMobileMoneyRequest.swift
//  RaveSDK
//
//  Created by Rotimi Joshua on 02/09/2020.
//

import Foundation

// MARK: - GhanaMobileMoneyRequest
struct GhanaMobileMoneyRequest: Codable {
    let txRef, amount, currency, voucher: String?
    let network, email, phoneNumber, fullname: String?
    let redirecturl: String? = "https://webhook.site/finish"

    enum CodingKeys: String, CodingKey {
        case txRef = "tx_ref"
        case amount, currency, voucher, network, email
        case phoneNumber = "phone_number"
        case redirecturl = "redirect_url"
        case fullname
    }
}

// MARK: - GhanaMobileMoneyResponse
struct GhanaMobileMoneyResponse: Codable,FlutterChargeResponse {
    let status, message: String?
    let  meta: Meta?
}
