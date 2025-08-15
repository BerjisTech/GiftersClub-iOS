//
//  Container.swift
//  RaveSDK
//
//  Created by Rotimi Joshua on 26/08/2020.
//

import Foundation
import Swinject
import SwinjectAutoregistration


extension Container {

    static let sharedContainer:Container = {
        let container  = Container()

       //REPOSITORIES

        container.autoregister(PaymentServicesRepository.self, initializer: PaymentServicesRepositoryImpl.init)

        container.autoregister(MobileMoneyRepository.self, initializer: MobileMoneyRepositoryImpl.init)
        
        container.autoregister(BankRepository.self, initializer: BankRepositoryImpl.init)
        
        container.autoregister(CardRepository.self, initializer: CardRepositoryImpl.init)


       //VIEWMODELS

        container.autoregister(PaymentServicesViewModel.self, initializer: PaymentServicesViewModel.init)

         container.autoregister(BankViewModel.self, initializer: BankViewModel.init)
        
         container.autoregister(MobileMoneyViewModel.self, initializer: MobileMoneyViewModel.init)
         container.autoregister(CardViewModel.self, initializer: CardViewModel.init)
        
        return container
    }()
}



