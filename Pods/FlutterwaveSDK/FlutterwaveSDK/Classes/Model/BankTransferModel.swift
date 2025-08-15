//
//  BankTransferModel.swift
//  Alamofire
//
//  Created by Rotimi Joshua on 02/09/2020.
//

import Foundation

// MARK: - BankTransferRequest
struct BankTransferRequest: Codable {
    let txRef, amount, email, phoneNumber: String?
    let currency: String?
    let duration, frequency: Double?
    let narration: String?
    let isPermanent: Bool?

    enum CodingKeys: String, CodingKey {
        case txRef = "tx_ref"
        case amount, email
        case phoneNumber = "phone_number"
        case currency, duration, frequency, narration
        case isPermanent = "is_permanent"
    }
}


// MARK: - BankTransferResponse
struct BankTransferResponse: Codable {
    let status, message: String?
    let meta: Meta?
}

