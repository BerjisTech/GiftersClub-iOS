//
//  File.swift
//  FlutterwaveSDK
//
//  Created by Rotimi Joshua on 26/08/2020.
//

import Foundation
import RxSwift

protocol PaymentServicesRepository {
    
    func chargeCard(request:ChargeCardRequest) -> Observable<NetworkResult<ChargeCardResponse>>
    
    func validateCharge(request:ValidateChargeRequest) -> Observable<NetworkResult<ValidateChargeResponse>>
    
    func mpesaVerify(request:MpesaVerifyRequest) -> Observable<NetworkResult<MpesaVerifyResponse>>
    
    func pwbtVerify(request:PwbtVerifyRequest) -> Observable<NetworkResult<PwbtVerifyResponse>>
   
}

class PaymentServicesRepositoryImpl: BaseRepository, PaymentServicesRepository {
    
    func chargeCard(request: ChargeCardRequest) -> Observable<NetworkResult<ChargeCardResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.chargeCard, request: request, response: ChargeCardResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }
    
    
    func validateCharge(request: ValidateChargeRequest) -> Observable<NetworkResult<ValidateChargeResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.validateCard, request: request, response: ValidateChargeResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }
    
    func mpesaVerify(request: MpesaVerifyRequest) -> Observable<NetworkResult<MpesaVerifyResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.mpesaVerify, request: request, response: MpesaVerifyResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }
    
    func pwbtVerify(request: PwbtVerifyRequest) -> Observable<NetworkResult<PwbtVerifyResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.pwbtVerify, request: request, response: PwbtVerifyResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }
  
}
