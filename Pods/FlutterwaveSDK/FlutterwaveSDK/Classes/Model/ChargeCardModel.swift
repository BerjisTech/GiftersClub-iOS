//
//  ChargeCardModel.swift
//  RaveSDK
//
//  Created by Rotimi Joshua on 26/08/2020.
//

import Foundation


struct ChargeCardRequest: Codable {

    let client:String?
}


struct ChargeCardResponse:Codable,FlutterChargeResponse {
    let status, message: String?
    let data: ChargeData?
    let meta: Meta?
}

// MARK: - DataClass
struct ChargeData:Codable {
    let id: Int?
    let txRef, flwRef, deviceFingerprint: String?
    let amount, chargedAmount, appFee, merchantFee: Double?
    let processorResponse, authModel, currency, ip: String?
    let narration, status, authURL, paymentType: String?
    let plan: String?
    let fraudStatus, chargeType, createdAt: String?
    let accountID: Int?
    let customer: Customer?
    let card: CardData?
    
    enum CodingKeys: String, CodingKey {
         case id
         case txRef = "tx_ref"
         case flwRef = "flw_ref"
         case deviceFingerprint = "device_fingerprint"
         case amount
         case chargedAmount = "charged_amount"
         case appFee = "app_fee"
         case merchantFee = "merchant_fee"
         case processorResponse = "processor_response"
         case authModel = "auth_model"
         case currency, ip, narration, status
         case authURL = "auth_url"
         case paymentType = "payment_type"
         case plan
         case fraudStatus = "fraud_status"
         case chargeType = "charge_type"
         case createdAt = "created_at"
         case accountID = "account_id"
         case customer, card
     }
}

// MARK: - Card
public struct CardData:Codable {
    let first6Digits, last4Digits, issuer, country: String?
    let type, expiry: String?
    
    enum CodingKeys: String, CodingKey {
           case first6Digits = "first_6digits"
           case last4Digits = "last_4digits"
           case issuer, country, type, expiry
       }
}

// MARK: - Customer
public struct Customer:Codable {
    let id: Int?
    let phoneNumber: String?
    let name, email, createdAt: String?
    enum CodingKeys: String, CodingKey {
          case id
          case phoneNumber = "phone_number"
          case name, email
          case createdAt = "created_at"
      }
}

// MARK: - Meta
struct Meta:Codable {
    let authorization: Authorization?
}

// MARK: - Authorization
struct Authorization:Codable {
    let mode, endpoint,redirect,note,validateInstructions, transferReference, accountExpiration, transferBank, transferAccount, transferNote: String?
    let transferAmount:Double?
    
    enum CodingKeys: String, CodingKey {
        case transferReference = "transfer_reference"
        case transferBank = "transfer_bank"
        case accountExpiration = "account_expiration"
        case transferAccount = "transfer_account"
        case transferNote = "transfer_note"
        case transferAmount = "transfer_amount"
        case validateInstructions = "validate_instructions"
        case mode,endpoint,redirect,note
    
    }
}


protocol FlutterChargeResponse {
    var meta:Meta? { get }
}


extension ChargeData {
    func toFlutterResponse() -> FlutterwaveDataResponse{
        return FlutterwaveDataResponse(txRef: txRef, flwRef: flwRef, deviceFingerprint: deviceFingerprint, amount: amount, chargedAmount: chargedAmount, appFee: appFee, merchantFee: merchantFee, processorResponse: processorResponse, authModel: authModel, currency: currency, ip: ip, narration: narration, status: status, authURL: authURL, paymentType: paymentType, fraudStatus: fraudStatus, chargeType: chargeType, createdAt: createdAt, plan: plan, id: id, accountID: accountID, customer: customer, card: card)
    }
}
