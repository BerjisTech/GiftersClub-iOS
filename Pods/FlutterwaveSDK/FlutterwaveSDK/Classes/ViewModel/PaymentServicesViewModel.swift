//
//  PaymentServicesViewModel.swift
//  RaveSDK
//
//  Created by Rotimi Joshua on 26/08/2020.
//

import UIKit

import Foundation
import RxSwift
import Swinject

class PaymentServicesViewModel: BaseViewModel{
    
    static let sharedViewModel: PaymentServicesViewModel = Container.sharedContainer.resolve(PaymentServicesViewModel.self)!
    
    let paymentServicesRepository: PaymentServicesRepository
    let moveToPin = PublishSubject<String>()
    let moveToOTP = PublishSubject<ChargeCardResponse>()
    let moveToWebView = PublishSubject<ChargeCardResponse>()
    let moveToAddressVerification = PublishSubject<ChargeCardResponse>()
    let chargeCardResponse = PublishSubject<ChargeCardResponse>()
    let validateCharge = PublishSubject<ValidateChargeResponse>()
    let mpesaVerifyResponse = PublishSubject<MpesaVerifyResponse>()
    let pwbtVerifyResponse = PublishSubject<PwbtVerifyResponse>()
    var flwRef = ""
    var txRef = ""
    let pendingTransactionAlert =  PublishSubject<String>()
    var retryCount = 0
    var pwtRetryCount = 0
    init(paymentServicesRepository: PaymentServicesRepository){
        self.paymentServicesRepository = paymentServicesRepository
    }
    
    
    func chargeCard(client: String) {
        let request = ChargeCardRequest(client: client)
        makeAPICallRx(request: request, apiRequest: paymentServicesRepository.chargeCard(request:), successHandler: chargeCardResponse,onSuccessOperation: {response in
            let authMode = response.meta?.authorization?.mode ?? ""
            switch authMode{
            case "pin":
                self.moveToPin.onNext("")
            case "otp":
                self.moveToOTP.onNext(response)
            case "redirect":
                self.moveToWebView.onNext(response)
            case "avs_noauth":
                self.moveToAddressVerification.onNext(response)
            default:
                break
            }
            
        },apiName: .initCardCharge,apiErrorName: .initCardChargeError)
    }
    
    func validateCharge(otp: String, flwRef: String, type:String) {
        let request = ValidateChargeRequest(otp: otp, flwRef:flwRef, type:type)
        makeAPICallRx(request: request, apiRequest: paymentServicesRepository.validateCharge(request:), successHandler: validateCharge,onSuccessOperation: { response in
            self.flwRef = response.data?.flwRef ?? ""
            PaymentServicesViewModel.sharedViewModel.mpesaVerify(flwRef: PaymentServicesViewModel.sharedViewModel.flwRef)
        }, apiName: .accountChargeValidate, apiErrorName: .accountChargeValidateError) 
    }
    
    
    func mpesaVerify(flwRef: String) {
        self.isLoading.onNext(true)
        let request = MpesaVerifyRequest(flwRef:flwRef)
        makeAPICallRx(request: request, apiRequest: paymentServicesRepository.mpesaVerify(request:), successHandler: mpesaVerifyResponse,showLoading: false,onSuccessOperation: {response in
            let status = response.getStatus()
            switch status{
            case .PENDING:
                self.handleRetry(currentRetryCount:PaymentServicesViewModel.sharedViewModel.retryCount,flwRef:flwRef)
            case .SUCCESS:
                self.isLoading.onNext(false)
            case .SUCCESS2:
                self.isLoading.onNext(false)
            case .FAILED:
                self.isLoading.onNext(false)
            }
            if(CardViewModel.sharedViewModel.saveCard && ( status == .SUCCESS || status == .SUCCESS2 )){
                CardViewModel.sharedViewModel.saveCard(processorReference: flwRef)
            }
            CardViewModel.sharedViewModel.saveCard = false
        }, apiName: .accountVerify, apiErrorName: .accountChargeValidateError)
    }
    
    
    private func handleRetry(currentRetryCount:Int,flwRef:String){
        let seconds = 10.0
        let maxRetryCount = 10
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if(currentRetryCount != maxRetryCount){
                PaymentServicesViewModel.sharedViewModel.mpesaVerify(flwRef: flwRef)
                PaymentServicesViewModel.sharedViewModel.retryCount += 1
                self.pendingTransactionAlert.onNext("Your transaction is still pending try again")
            }else{
                self.isLoading.onNext(false)
               
                PaymentServicesViewModel.sharedViewModel.retryCount = 0
                self.pendingTransactionAlert.onNext("Your transaction is still pending try again")
                
            }
        }
    }
    
    
    
    
    func pwbtVerify(txRef: String){
        self.isLoading.onNext(true)
        let request = PwbtVerifyRequest(txRef:txRef)
        makeAPICallRx(request: request, apiRequest: paymentServicesRepository.pwbtVerify(request:), successHandler: pwbtVerifyResponse,showLoading: false,onSuccessOperation: {response in
            let status = response.getStatus()
            switch status{
            case .PENDING:
                self.handleRetryPwbtVerify(currentRetryCount:PaymentServicesViewModel.sharedViewModel.pwtRetryCount,txRef:txRef)
            case .SUCCESS:
                self.isLoading.onNext(false)
            case .SUCCESS2:
                self.isLoading.onNext(false)
            case .FAILED:
                self.isLoading.onNext(false)
            }
        }, apiName: .bankTransfer, apiErrorName: .bankTransferError)
    }
    
    private func handleRetryPwbtVerify(currentRetryCount:Int,txRef:String){
        let seconds = 10.0
        let maxRetryCount = 10
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if(currentRetryCount != maxRetryCount){
                PaymentServicesViewModel.sharedViewModel.pwbtVerify(txRef: txRef)
                PaymentServicesViewModel.sharedViewModel.pwtRetryCount += 1

            }else{
                PaymentServicesViewModel.sharedViewModel.pwtRetryCount = 0
                self.isLoading.onNext(false)
                self.pendingTransactionAlert.onNext("Your transaction is still pending try again")
            }
        }
    }
    
}

enum PaymentState:String {
    case PENDING = "pending"
    case SUCCESS = "successful"
    case FAILED = "failed"
    case SUCCESS2 = "success"
}

extension MpesaVerifyResponse{
    
    func getStatus() -> PaymentState{
        let status = self.data?.status ?? "failed"
        switch status {
        case PaymentState.PENDING.rawValue:
            return PaymentState.PENDING
        case PaymentState.SUCCESS.rawValue:
            return PaymentState.SUCCESS
        case PaymentState.FAILED.rawValue:
            return PaymentState.FAILED
        case PaymentState.SUCCESS2.rawValue:
            return PaymentState.SUCCESS
        default:
            return PaymentState.FAILED
        }
    }
}



extension PwbtVerifyResponse{
    
    func getStatus() -> PaymentState{
        let status = self.data?.status ?? "failed"
        switch status {
        case PaymentState.PENDING.rawValue:
            return PaymentState.PENDING
        case PaymentState.SUCCESS.rawValue:
            return PaymentState.SUCCESS
        case PaymentState.FAILED.rawValue:
            return PaymentState.FAILED
        case PaymentState.SUCCESS2.rawValue:
            return PaymentState.SUCCESS
        default:
            return PaymentState.FAILED
        }
    }
}
