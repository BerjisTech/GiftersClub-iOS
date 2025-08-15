//
//  CardViewModel.swift
// FlutterwaveSDK
//
//  Created by Rotimi Joshua on 15/09/2020.
//

import UIKit

import RxSwift
import Swinject

class CardViewModel: BaseViewModel{
    
    static let sharedViewModel: CardViewModel = Container.sharedContainer.resolve(CardViewModel.self)!
 
 
    let cardRepository: CardRepository
    let fetchCardResponse = PublishSubject<FetchSavedCardResponse>()
    let saveCardResponse = PublishSubject<SaveCardNewResponse>()
    let removeCardResponse = PublishSubject<RemoveCardResponse>()
    let sendCardOtpResponse = PublishSubject<SendCardOTPResponse>()
    let chargeSavedCardResponse = PublishSubject<ChargeSavedCardResponse>()
    let fetchCardFailed = PublishSubject<String>()
    let removeCardFailed = PublishSubject<String>()
    var saveCard = false
    
    var flwRef = ""
    
    init(cardRepository: CardRepository){
        self.cardRepository = cardRepository
    }
   
    func fetchCard() {
        let request = FetchSavedCardRequest(deviceKey: FlutterwaveConfig.sharedConfig().phoneNumber, publicKey: FlutterwaveConfig.sharedConfig().publicKey)
        makeAPICallRx(request: request, apiRequest: cardRepository.fetchCard(request:), successHandler: fetchCardResponse,showError: false, onFailureOperation: { [weak self] in
            self?.fetchCardFailed.onNext("")
        }, apiName: .fetchCard, apiErrorName: .fetchCardError
    )}
  
    func saveCard(processorReference: String) {
        let request = SaveCardNewRequest(processorReference:processorReference, publicKey: FlutterwaveConfig.sharedConfig().publicKey, deviceEmail: FlutterwaveConfig.sharedConfig().email, device: UIDevice.current.identifierForVendor?.uuidString, deviceKey: FlutterwaveConfig.sharedConfig().phoneNumber)
        makeAPICallRx(request: request, apiRequest: cardRepository.saveCard(request:), successHandler: saveCardResponse
                      ,showLoading: false , apiName: .saveCard, apiErrorName: .saveCardError)
        
    }
    
    func removeCard(cardHash: String) {
        let request = RemoveCardRequest(mobileNumber: FlutterwaveConfig.sharedConfig().phoneNumber, publicKey: FlutterwaveConfig.sharedConfig().publicKey, cardHash: cardHash)
        makeAPICallRx(request: request, apiRequest: cardRepository.removeCard(request:), successHandler: removeCardResponse,onFailureOperation: { [weak self] in
            self?.removeCardFailed.onNext("")
        },handleFailureOperation: { [weak self] response in
            self?.removeCardFailed.onNext(response.message ?? "Error")
        }, apiName: .removeCard, apiErrorName: .removeCardError
       )}
    
    
    func sendCardOtp(cardHash: String) {
        let request = SendCardOTPRequest(cardHash:cardHash, deviceKey:FlutterwaveConfig.sharedConfig().phoneNumber, publicKey: FlutterwaveConfig.sharedConfig().publicKey)
        makeAPICallRx(request: request, apiRequest: cardRepository.sendCardOtp(request:), successHandler: sendCardOtpResponse, apiName: .sendSavedCardOTP, apiErrorName: .sendSavedCardOTPError
         )}
    
    
    func chargeSavedCard(client: String) {
        let request = ChargeSavedCardRequest(publicKey:FlutterwaveConfig.sharedConfig().publicKey, client:client, alg: "3DES-24")
        makeAPICallRx(request: request, apiRequest: cardRepository.chargeSavedCard(request:), successHandler: chargeSavedCardResponse, apiName: .chargeSavedCard, apiErrorName: .chargeSavedCardError
         )}
    
}

