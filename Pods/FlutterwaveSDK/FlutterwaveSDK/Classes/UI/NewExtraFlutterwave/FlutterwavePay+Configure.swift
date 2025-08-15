//
//  FlutterwavePay+Configure.swift
//  FlutterwaveSDK
//
//  Created by Rotimi Joshua on 07/09/2020.
//

import UIKit

extension FlutterwavePayViewController {
    
    
    func configureUssdBankView(){
        ussdBankPicker = UIPickerView()
        ussdBankPicker.autoresizingMask  = [.flexibleWidth , .flexibleHeight]
        ussdBankPicker.delegate = self
        ussdBankPicker.dataSource = self
        ussdBankPicker.tag = 13
        self.selectUssdBankView.otherBanksTextField.delegate = self
        self.selectUssdBankView.otherBanksTextField.inputView = ussdBankPicker
        
        self.selectUssdBankView.otherBanksTextField.watchText(validationType: ValidatorType.requiredField(field: "select a Bank"), disposeBag: disposeBag)
        
        selectUssdBankView.PayButton.setTitle("PAY \(self.amount?.toCountryCurrency(code: FlutterwaveConfig.sharedConfig().currencyCode) ?? "")", for: .normal)
        
        self.selectUssdBankView.PayButton.rx.tap.subscribe(onNext: {
            
            let bankValid = self.selectUssdBankView.otherBanksTextField.validateAndShowError(validationType: ValidatorType.requiredField(field: "select a Bank"))
            self.selectUssdBankView.otherBanksTextField.resignFirstResponder()
            
            if(bankValid ){
                BankViewModel.sharedViewModel.ussd(amount: self.amount.orEmpty(), ussdBank: self.selectedUSSDBank)
            }
        }).disposed(by: disposableBag)
        
        BankViewModel.sharedViewModel.changeUSSDText.subscribe(onNext: { text in
            self.confirmUssdView.ussdCodeLabel.text = text
            
        } ).disposed(by: disposableBag)
        BankViewModel.sharedViewModel.referenceText.subscribe(onNext: { text in
            self.confirmUssdView.referenceCodeLabel.text = text
            
        } ).disposed(by: disposableBag)
        
        self.confirmUssdView.completePayment.rx.tap.subscribe(onNext: {
            PaymentServicesViewModel.sharedViewModel.mpesaVerify(flwRef: BankViewModel.sharedViewModel.flwRef)
            
        }).disposed(by: disposableBag)
        
        
        self.confirmUssdView.copyButton.rx.tap.subscribe(onNext: {
            let pasteboard = UIPasteboard.general
            pasteboard.string = BankViewModel.sharedViewModel.ussdBankText
            showSnackBarWithMessage(msg: "USSD code copied")
        }).disposed(by: disposableBag)
        
    }
    
    
    func configureBarter(){
        //        barterContentContainer.payButton.setTitle("PAY \(self.amount?.toCountryCurrency(code: RaveConfig.sharedConfig().currencyCode) ?? "")", for: .normal)
        //
        
        barterContentContainer.payButton.rx.tap.subscribe(onNext: {
//            self.showToast(message: "Your Toast Message")
            //            let pubKey = RaveConfig.sharedConfig().publicKey
            //            self.showWebView(url: "https://bartercheckout.herokuapp.com/?\(pubKey ?? "")&flwref=PWB_3228939269",ref:"")
            showSnackBarWithMessage(msg: "Coming soon")
        }).disposed(by: disposableBag)
    }
    
    
    func configureBankTransfer(){
        bankTransferViewOne.payButton.setTitle("PAY \(self.amount?.toCountryCurrency(code: FlutterwaveConfig.sharedConfig().currencyCode) ?? "")", for: .normal)
        
        bankTransferViewOne.payButton.rx.tap.subscribe(onNext: {
            BankViewModel.sharedViewModel.bankTransfer(amount: self.amount.orEmpty())
        }).disposed(by: disposableBag)
        
        
        self.bankTransferViewTwo.copyButton.rx.tap.subscribe(onNext: {
            let pasteboard = UIPasteboard.general
            pasteboard.string = self.bankTransferViewTwo.accountValue.text.orEmpty()
            showSnackBarWithMessage(msg: "Beneficiary account number copied")
        }).disposed(by: disposableBag)
        
        self.bankTransferViewTwo.completePayment.rx.tap.subscribe(onNext: {
            
            PaymentServicesViewModel.sharedViewModel.pwbtVerify(txRef: FlutterwaveConfig.sharedConfig().transcationRef.orEmpty())
            
        }).disposed(by: disposableBag)
    }
    
}

