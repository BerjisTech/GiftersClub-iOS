//
//  MobileMoneyViewModel.swift
//  RaveSDK
//
//  Created by Rotimi Joshua on 02/09/2020.
//

import RxSwift
import Swinject

class MobileMoneyViewModel: BaseViewModel{
    
    static let sharedViewModel: MobileMoneyViewModel = Container.sharedContainer.resolve(MobileMoneyViewModel.self)!
    
    let mobileMoneyRepository: MobileMoneyRepository
    let ghanaMoneyResponse = PublishSubject<GhanaMobileMoneyResponse>()
    let rwandaMoneyResponse = PublishSubject<RwandaMobileMoneyResponse>()
    let ugandaMoneyResponse = PublishSubject<UgandaMobileMoneyResponse>()
    let zambiaMoneyResponse = PublishSubject<ZambiaMobileMoneyResponse>()
    let mpesaMoneyResponse = PublishSubject<MpesaResponse>()
    let francoPhoneResponse = PublishSubject<FrancophoneMobileMoneyResponse>()
    let voucherChargeResponse = PublishSubject<VoucherChargeResponse>()
    var flwRef = ""
    
    init(mobileMoneyRepository: MobileMoneyRepository){
        self.mobileMoneyRepository = mobileMoneyRepository
    }
  
    func ghanaMoney(amount: String, voucher: String, network: String, phoneNumber: String){
        let request = GhanaMobileMoneyRequest(txRef: FlutterwaveConfig.sharedConfig().transcationRef, amount: amount, currency: FlutterwaveConfig.sharedConfig().currencyCode, voucher: voucher, network: network, email: FlutterwaveConfig.sharedConfig().email, phoneNumber: phoneNumber, fullname: "\(FlutterwaveConfig.sharedConfig().firstName.orEmpty()) \(FlutterwaveConfig.sharedConfig().lastName.orEmpty())")
        makeAPICallRx(request: request, apiRequest: mobileMoneyRepository.ghanaMoney(request:), successHandler: ghanaMoneyResponse,onSuccessOperation: {response in
            self.checkAuth(response: response, flwRef: "",source: .ghanaMoney)
        }, apiName: .ghanaMoney, apiErrorName: .ghanaMoneyError)
    }
    
    func rwandaMoney(amount: String, network:String, phoneNumber: String) {
        let request = RwandaMobileMoneyRequest(txRef: FlutterwaveConfig.sharedConfig().transcationRef, amount: amount, currency: FlutterwaveConfig.sharedConfig().currencyCode, network: network, email: FlutterwaveConfig.sharedConfig().email, phoneNumber: phoneNumber, fullname: "\(FlutterwaveConfig.sharedConfig().firstName.orEmpty()) \(FlutterwaveConfig.sharedConfig().lastName.orEmpty())")
        makeAPICallRx(request: request, apiRequest: mobileMoneyRepository.rwandaMoney(request:), successHandler: rwandaMoneyResponse, onSuccessOperation: {response in
            self.checkAuth(response: response, flwRef: "",source: .rwandaMoney)
        }, apiName: .rwandaMoney, apiErrorName: .rwandaMoneyError)
    }
    
    func ugandaMoney(amount: String, phoneNumber: String) {
        let request = UgandaMobileMoneyRequest(txRef: FlutterwaveConfig.sharedConfig().transcationRef, amount: amount, email: FlutterwaveConfig.sharedConfig().email, phoneNumber: phoneNumber, currency: FlutterwaveConfig.sharedConfig().currencyCode, network: "MTN")
        makeAPICallRx(request: request, apiRequest: mobileMoneyRepository.ugandaMoney(request:), successHandler: ugandaMoneyResponse, onSuccessOperation: {response in
            self.checkAuth(response: response, flwRef: "",source: .ugandaMoney)
        }, apiName: .zambiaMoney, apiErrorName: .zambiaMoneyError)
    }
    
    func zambiaMoney(amount: String, phoneNumber: String, network: String) {
        let request = ZambiaMobileMoneyRequest(txRef: FlutterwaveConfig.sharedConfig().transcationRef, amount: amount, currency: FlutterwaveConfig.sharedConfig().currencyCode, network: network, email: FlutterwaveConfig.sharedConfig().email, phoneNumber: phoneNumber, fullname: "\(FlutterwaveConfig.sharedConfig().firstName.orEmpty()) \(FlutterwaveConfig.sharedConfig().lastName.orEmpty())")
        makeAPICallRx(request: request, apiRequest: mobileMoneyRepository.zambiaMoney(request:), successHandler: zambiaMoneyResponse, onSuccessOperation: {response in
            self.checkAuth(response: response, flwRef: "", source: .zambiaMoney)
        }, apiName: .zambiaMoney, apiErrorName: .zambiaMoneyError)
    }
    
    func mpesaMoney(amount: String, phoneNumber: String) {
        let request = MpesaRequest(txRef: FlutterwaveConfig.sharedConfig().transcationRef, amount: amount, currency: FlutterwaveConfig.sharedConfig().currencyCode, email:FlutterwaveConfig.sharedConfig().email, phoneNumber: phoneNumber, fullname: "\(FlutterwaveConfig.sharedConfig().firstName.orEmpty()) \(FlutterwaveConfig.sharedConfig().lastName.orEmpty())")
        makeAPICallRx(request: request, apiRequest: mobileMoneyRepository.mpesa(request:), successHandler: mpesaMoneyResponse,onSuccessOperation: { response in
            self.flwRef = response.data?.flwRef ?? ""
            PaymentServicesViewModel.sharedViewModel.mpesaVerify(flwRef: MobileMoneyViewModel.sharedViewModel.flwRef)
            
        }, apiName: .mpesaMoney, apiErrorName: .mpesaMoneyError)
    }
    
    
    
    func francoPhoneMoney(amount: String, phoneNumber: String, country:String) {
        let request = FrancophoneMobileMoneyRequest(txRef: FlutterwaveConfig.sharedConfig().transcationRef, amount: amount, currency: FlutterwaveConfig.sharedConfig().currencyCode, email: FlutterwaveConfig.sharedConfig().email, phoneNumber: phoneNumber, country: country, fullname: "\(FlutterwaveConfig.sharedConfig().firstName.orEmpty()) \(FlutterwaveConfig.sharedConfig().lastName.orEmpty())")
        makeAPICallRx(request: request, apiRequest: mobileMoneyRepository.francophoneMoney(request:), successHandler: francoPhoneResponse, onSuccessOperation: {response in
            self.checkAuth(response: response, flwRef: response.data?.flwRef ?? "", source: .francophoneMoney)
        }, apiName: .francoPhoneMoney, apiErrorName: .francoPhoneMoneyError)
    }
    
    func voucherCharge(txRef: String, amount: String, currency: String, pin:String, email: String, phoneNumber: String, fullName: String) {
        let request = VoucherChargeRequest(txRef: txRef, amount: amount, currency: currency, pin: pin, email: email, phoneNumber: phoneNumber, fullname: fullName)
          makeAPICallRx(request: request, apiRequest: mobileMoneyRepository.voucherCharge(request:), successHandler: voucherChargeResponse)
      }
}




