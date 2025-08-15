//
//  MobileMoneyRepository.swift
//  FlutterwaveSDK
//
//  Created by Rotimi Joshua on 02/09/2020.
//

import RxSwift

protocol MobileMoneyRepository {
    
    func mpesa(request:MpesaRequest) -> Observable<NetworkResult<MpesaResponse>>
       
    func ghanaMoney(request:GhanaMobileMoneyRequest) -> Observable<NetworkResult<GhanaMobileMoneyResponse>>
    
    func rwandaMoney(request:RwandaMobileMoneyRequest) -> Observable<NetworkResult<RwandaMobileMoneyResponse>>
    
    func ugandaMoney(request:UgandaMobileMoneyRequest) -> Observable<NetworkResult<UgandaMobileMoneyResponse>>
    
    func zambiaMoney(request:ZambiaMobileMoneyRequest) -> Observable<NetworkResult<ZambiaMobileMoneyResponse>>
    
    func francophoneMoney(request:FrancophoneMobileMoneyRequest) -> Observable<NetworkResult<FrancophoneMobileMoneyResponse>>
    
    func voucherCharge(request:VoucherChargeRequest) -> Observable<NetworkResult<VoucherChargeResponse>>
    
}

class MobileMoneyRepositoryImpl: BaseRepository, MobileMoneyRepository {
   
    
    func mpesa(request: MpesaRequest) -> Observable<NetworkResult<MpesaResponse>> {
          return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.mpesa, request: request, response: MpesaResponse.self, successCondition: { response in
              response.status == "success"
          }, errorMessage: {response in
              response.message ?? "Something went wrong"
          })
      }
   
    func ghanaMoney(request: GhanaMobileMoneyRequest) -> Observable<NetworkResult<GhanaMobileMoneyResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.ghanaMoney, request: request, response: GhanaMobileMoneyResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }
    
    func rwandaMoney(request: RwandaMobileMoneyRequest) -> Observable<NetworkResult<RwandaMobileMoneyResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.rwandaMoney, request: request, response: RwandaMobileMoneyResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }
    
    func ugandaMoney(request: UgandaMobileMoneyRequest) -> Observable<NetworkResult<UgandaMobileMoneyResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.ugandaMoney, request: request, response: UgandaMobileMoneyResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }
    
    func zambiaMoney(request: ZambiaMobileMoneyRequest) -> Observable<NetworkResult<ZambiaMobileMoneyResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.zambiaMoney, request: request, response: ZambiaMobileMoneyResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }
    
    func francophoneMoney(request: FrancophoneMobileMoneyRequest) -> Observable<NetworkResult<FrancophoneMobileMoneyResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.francophoneMoney, request: request, response: FrancophoneMobileMoneyResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }
    
  func voucherCharge(request: VoucherChargeRequest) -> Observable<NetworkResult<VoucherChargeResponse>> {
             return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.voucherCharge, request: request, response: VoucherChargeResponse.self, successCondition: { response in
                   response.status == "success"
               }, errorMessage: {response in
                   response.message ?? "Something went wrong"
               })
     }
     
}
