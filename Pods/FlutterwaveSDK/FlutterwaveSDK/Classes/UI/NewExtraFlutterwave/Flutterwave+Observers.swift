//
//  Flutterwave+Observers.swift
//  FluuterwaveSDK
//
//  Created by Rotimi Joshua on 02/09/2020.
//

import RxSwift
import UIKit

extension FlutterwavePayViewController {
    
    func setUpObservers(){
        setUpLoading()
        setUpNextActionObservers()
        setUpErrorObservers()
        setUpSuccessObservers()
        fetchBanks()
    }
    
    func setUpNextActionObservers(){
        moveToWebObserver()
        PaymentServicesViewModel.sharedViewModel.moveToPin.subscribe(onNext: { value in
            self.showPin()
        } ).disposed(by: disposableBag)
        
        
        
        setUpMoveToOTP(baseViewModel: BankViewModel.sharedViewModel, action: { processorResponse,flwRef,source in
                        self.onResponseViewChange(message: processorResponse, flwRef: flwRef, source: source)
                        self.flutterwaveCardClient.transactionReference = flwRef
                        self.showOTP(message: processorResponse, flwRef: flwRef, otpType: .card)})
        
        PaymentServicesViewModel.sharedViewModel.moveToAddressVerification.subscribe(onNext: {response in
            self.showBillingAddress()
        }).disposed(by: disposableBag)
        
        
        PaymentServicesViewModel.sharedViewModel.moveToOTP.subscribe(onNext: { value in
            self.showOTP(message: value.data?.processorResponse ?? "", flwRef: value.data?.flwRef ?? "", otpType: .card)
        } ).disposed(by: disposableBag)
        
        
    }
    
    func moveToWebObserver(){
        PaymentServicesViewModel.sharedViewModel.moveToWebView.subscribe(onNext: {response in
            let ref = response.data?.flwRef.orEmpty()
            self.showWebView(url: response.meta?.authorization?.redirect.orEmpty(),ref:ref)
        }).disposed(by: disposableBag)
        
        setUpMoveToWebView(baseViewModel: MobileMoneyViewModel.sharedViewModel, action: {url,ref in
            self.showWebView(url: url,ref:ref)
        })
        setUpMoveToWebView(baseViewModel: BankViewModel.sharedViewModel, action: {url,ref in
            self.showWebView(url: url,ref:ref)
        })
        CardViewModel.sharedViewModel.chargeSavedCardResponse.subscribe(onNext: {response in
            self.showWebView(url: response.data?.authurl,ref:response.data?.flwRef)
        } ).disposed(by: disposeBag)
    }
    func setUpLoading(){
        setUpLoadingObservers(baseViewModel: PaymentServicesViewModel.sharedViewModel)
        setUpLoadingObservers(baseViewModel: MobileMoneyViewModel.sharedViewModel)
        setUpLoadingObservers(baseViewModel: BankViewModel.sharedViewModel)
        setUpLoadingObservers(baseViewModel: CardViewModel.sharedViewModel)
    }
    
    
    func setUpSuccessObservers(){
        PaymentServicesViewModel.sharedViewModel.mpesaVerifyResponse.subscribe(onNext: { response in
            switch response.getStatus(){
            case .PENDING:
                break
            case .SUCCESS:
                self.flutterwaveCardClient.chargeSuccess!(response.data?.flwRef,response.data?.toFlutterResponse())
            case .SUCCESS2:
                self.flutterwaveCardClient.chargeSuccess!(response.data?.flwRef,response.data?.toFlutterResponse())
            case .FAILED:
                self.dismiss(animated: true, completion: nil)
                self.delegate?.tranasctionFailed(flwRef: response.data?.flwRef, responseData: response.data?.toFlutterResponse())
                
            }
            
        }).disposed(by: disposableBag)
        
        PaymentServicesViewModel.sharedViewModel.pendingTransactionAlert.subscribe(onNext: { pendingText in
            //DIsplay Toast
            showSnackBarWithMessage(msg: pendingText, style: .error)
        } ).disposed(by: disposableBag)
        
        
        
        
        
        BankViewModel.sharedViewModel.ussdResponse.subscribe(onNext: { response in
            self.showUssd()
        }).disposed(by: disposableBag)
        //
        
        
        BankViewModel.sharedViewModel.bankTransferResponse.subscribe(onNext: { response in
            self.bankTransferViewTwo.accountValue.text = response.meta?.authorization?.transferAccount
            let currency = "₦"
            self.bankTransferViewTwo.amountValue.text = (currency + self.amount.orEmpty())
            self.bankTransferViewTwo.bankValue.text = response.meta?.authorization?.transferBank
            self.bankTransferViewTwo.beneficiaryValue.text = response.meta?.authorization?.transferAccount
            self.showBankTransferViewTwo()
        }).disposed(by: disposableBag)
        
        
        BankViewModel.sharedViewModel.ukAccountResponse.subscribe(onNext: { response in
            self.ukDetailsViewContainer.accountNumberValue.text = "4327122"
            let currency = "£"
            self.ukDetailsViewContainer.amountValue.text = (currency + self.amount.orEmpty())
            self.ukDetailsViewContainer.sortCodeValue.text = "04-00-53"
            self.ukDetailsViewContainer.beneficiaryNameLabelVlaue.text = "Barter Funding"
            self.ukDetailsViewContainer.referenceNumberValue.text = response.data?.flwRef
            self.showUkDetailsView()
        }).disposed(by: disposableBag)
    }
    
    
    
    func setUpErrorObservers(){
        BankViewModel.sharedViewModel.error.subscribe(onNext: { errorMessage in
            DispatchQueue.main.async {
                self.flutterwaveCardClient.error!(errorMessage,nil)
//                self.delegate?.tranasctionFailed(flwRef: nil,responseData: nil)
            }
        }).disposed(by: disposableBag)
        
        BankViewModel.sharedViewModel.error.observeOn(MainScheduler.instance).subscribe(onNext: { errorMessage in
            self.flutterwaveCardClient.error!(errorMessage,nil)
        }).disposed(by: disposableBag)
        
        PaymentServicesViewModel.sharedViewModel.error.subscribe(onNext: { errorMessage in
            DispatchQueue.main.async {
                self.flutterwaveCardClient.error!(errorMessage,nil)
            }
            
        }).disposed(by: disposableBag)
        
        CardViewModel.sharedViewModel.error.subscribe(onNext: { errorMessage in
            DispatchQueue.main.async {
                self.flutterwaveCardClient.error!(errorMessage,nil)
            }
            
        }).disposed(by: disposableBag)
        
        MobileMoneyViewModel.sharedViewModel.error.subscribe(onNext: { errorMessage in
            DispatchQueue.main.async {
                self.flutterwaveCardClient.error!(errorMessage,nil)
            }
        }).disposed(by: disposableBag)
        
    }
    
    
    func onResponseViewChange(message:String, flwRef:String, source:TransactionSource){
        switch source{
        case .nigerianBankTransfer:
            ShowOtpNigeriaBank(message: message, flwRef: flwRef)
        case .ghanaMoney:
            print("")
        case .ugandaMoney:
            print("")
        case .rwandaMoney:
            print("")
        case .zambiaMoney:
            print("")
        case .francophoneMoney:
            print("")
        }
    }
    
    
    func ShowOtpNigeriaBank(message:String, flwRef:String){
        
        self.accountOtpContentContainer.otpTextField.watchText(validationType: ValidatorType.requiredField(field: "OTP"), disposeBag: disposeBag)
        accountOtpContentContainer.otpTextField.rx.text.orEmpty
            .map { String($0.prefix(6)) }
            .bind(to: accountOtpContentContainer.otpTextField.rx.text)
            .disposed(by: disposeBag)
        self.accountOtpContentContainer.isHidden = false
        self.accountFormContainer.alpha = 0
        accountOtpContentContainer.otpMessage.text = message
        
        accountOtpContentContainer.otpButton.rx.tap.subscribe(onNext: {
            
            self.accountOtpContentContainer.otpTextField.resignFirstResponder()
            
            let otpValid = self.accountOtpContentContainer.otpTextField.validateAndShowError(validationType: ValidatorType.requiredField(field: "OTP"))
            if(otpValid){
                PaymentServicesViewModel.sharedViewModel.validateCharge(otp: self.accountOtpContentContainer.otpTextField.text.orEmpty(), flwRef: flwRef, type: "account")
            }
        }).disposed(by: disposableBag)
        
        UIView.animate(withDuration: 0.6, animations: {
            self.accountOtpContentContainer.alpha = 1
            self.accountFormContainer.alpha = 0
            self.selectBankAccountView.alpha = 0
        }) { (success) in
            self.accountFormContainer.isHidden = true
            self.selectBankAccountView.isHidden = true
        }
        
    }
    
    func fetchBanks(){
        BankViewModel.sharedViewModel.bankList.subscribe(onNext: {response in
            self.banks = response
        }).disposed(by: disposeBag)
        BankViewModel.sharedViewModel.getBanks()
        
    }
    
}



