//
//  PaymentOptionModel.swift
//  FlutterwaveSDK
//
//  Created by Rotimi Joshua on 01/10/2020.
//  Copyright © 2020 Flutterwave. All rights reserved.
//

import Foundation

public enum PaymentOption {
  case debitCard
  case bankAccount
  case bankTransfer
  case mobileMoney
  case ussd
  case voucherPayment
  case barter
}



public enum countryBanks: String {
  case nigeria
  case kenya
  case ghana
  case rwanda
  case zambia
  case cameroon
  case southAfrica
  case côtedIvoire
  case tanzania
  case uganda
}
