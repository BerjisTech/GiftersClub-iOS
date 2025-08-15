//
//  BankRepository.swift
//  FlutterwaveSDK
//
//  Created by Rotimi Joshua on 02/09/2020.
//

import Foundation
import RxSwift

protocol BankRepository {
   

    func accountPayment(request:AccountPaymentRequest) -> Observable<NetworkResult<AccountPaymentResponse>>
    
    func bankTransfer(request:BankTransferRequest) -> Observable<NetworkResult<BankTransferResponse>>
    
    func ukAccountsPayments(request:UKAccountPaymentsRequest) -> Observable<NetworkResult<UKAccountPaymentsResponse>>
    
    func ussd(request:USSDRequest) -> Observable<NetworkResult<USSDResponse>>
    
    func getbank() -> Observable<NetworkResult<[Bank]>>
    
    func nigeriaBankTransfer(request:NigeriaBankTransferRequest) -> Observable<NetworkResult<NigeriaBankTransferResponse>>
}

class BankRepositoryImpl: BaseRepository, BankRepository {
   
    
   
    func accountPayment(request: AccountPaymentRequest) -> Observable<NetworkResult<AccountPaymentResponse>> {
          return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.nigeriaBankAccount, request: request, response: AccountPaymentResponse.self, successCondition: { response in
              response.status == "success"
          }, errorMessage: {response in
              response.message ?? "Something went wrong"
          })
      }
    
    
    func bankTransfer(request: BankTransferRequest) -> Observable<NetworkResult<BankTransferResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.bankTransfer, request: request, response: BankTransferResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }
    
    func ukAccountsPayments(request: UKAccountPaymentsRequest) -> Observable<NetworkResult<UKAccountPaymentsResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.ukAccountPayment, request: request, response: UKAccountPaymentsResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }
    
    func ussd(request: USSDRequest) -> Observable<NetworkResult<USSDResponse>> {
        return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.ussd, request: request, response: USSDResponse.self, successCondition: { response in
            response.status == "success"
        }, errorMessage: {response in
            response.message ?? "Something went wrong"
        })
    }
    
    func nigeriaBankTransfer(request: NigeriaBankTransferRequest) -> Observable<NetworkResult<NigeriaBankTransferResponse>> {
            return makeNetworkPostRequestRx(endPoint: VersionThreeServicesApi.nigeriaBankAccount, request: request, response: NigeriaBankTransferResponse.self, successCondition: { response in
                  response.status == "success"
              }, errorMessage: { response in
                  response.message ?? "Something went wrong"
                
            }, successAction: { response in
                
            }, failureAction:{ response in
            })
          }
    

    
    func getbank() -> Observable<NetworkResult<[Bank]>> {
        return makeOrderedNetworkGetRequest(endPoint: VersionTwoServicesApi.getBank, parameters: [:], response: [Bank].self, successCondition: { response in
            true
        }, errorMessage: {response in
             "Something went wrong(Bank List)"
        })
    }
}
