//
//  CardRepository.swift
//  FlutterwaveSDK
//
//  Created by Rotimi Joshua on 13/09/2020.
//


import Foundation
import RxSwift

protocol CardRepository {

    func saveCard(request:SaveCardNewRequest) -> Observable<NetworkResult<SaveCardNewResponse>>

    func fetchCard(request:FetchSavedCardRequest) -> Observable<NetworkResult<FetchSavedCardResponse>>

    func removeCard(request:RemoveCardRequest) -> Observable<NetworkResult<RemoveCardResponse>>

    func sendCardOtp(request:SendCardOTPRequest) -> Observable<NetworkResult<SendCardOTPResponse>>
    
    func chargeSavedCard(request:ChargeSavedCardRequest) -> Observable<NetworkResult<ChargeSavedCardResponse>>

}

class CardRepositoryImpl: BaseRepository, CardRepository {

    func saveCard(request: SaveCardNewRequest) -> Observable<NetworkResult<SaveCardNewResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionTwoServicesApi.saveCard, request: request, response: SaveCardNewResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }

    func fetchCard(request: FetchSavedCardRequest) -> Observable<NetworkResult<FetchSavedCardResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionTwoServicesApi.fetchCard, request: request, response: FetchSavedCardResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }

    func removeCard(request: RemoveCardRequest) -> Observable<NetworkResult<RemoveCardResponse>> {
           return makeNetworkPostRequestRx(endPoint: VersionTwoServicesApi.removeCard, request: request, response: RemoveCardResponse.self, successCondition: { response in
               response.status == "success"
           }, errorMessage: {response in
               response.message ?? "Something went wrong"
           })
       }
    
    func sendCardOtp(request: SendCardOTPRequest) -> Observable<NetworkResult<SendCardOTPResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionTwoServicesApi.otpSavedCard, request: request, response: SendCardOTPResponse.self, successCondition: { response in
                  response.status == "success"
              }, errorMessage: {response in
                  response.message ?? "Something went wrong"
              })
          }
    
    
    func chargeSavedCard(request: ChargeSavedCardRequest) -> Observable<NetworkResult<ChargeSavedCardResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionTwoServicesApi.chargeSavedCard, request: request, response: ChargeSavedCardResponse.self, successCondition: { response in
                  response.status == "success"
              }, errorMessage: {response in
                  response.message ?? "Something went wrong"
              })
          }

}
