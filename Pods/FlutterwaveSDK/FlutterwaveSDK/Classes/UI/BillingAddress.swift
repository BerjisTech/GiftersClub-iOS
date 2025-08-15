//
//  BillingAddress.swift
//  RaveTest
//
//  Created by Olusegun Solaja on 09/09/2019.
//  Copyright © 2019 Olusegun Solaja. All rights reserved.
//

import UIKit
import MaterialComponents

class BillingAddress: UIView {

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Enter your billing address"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        return label
    }()
    
    lazy var billingAddressTextField: MDCOutlinedTextField = {
           let text = MDCOutlinedTextField()
           text.backgroundColor = UIColor.white.withAlphaComponent(0.5)
           text.label.text = "Address"
           text.setFloatingLabelColor(.black, for: .normal)
           text.setFloatingLabelColor(.black, for: .editing)
           text.tintColor = .lightGray
           text.font = UIFont.systemFont(ofSize: 16, weight: .medium)
           text.setNormalLabelColor(.lightGray, for: .normal)
           text.setTextColor(.black, for: .editing)
           text.setTextColor(.black, for: .normal)
           text.autoresizingMask = [.flexibleBottomMargin, .flexibleTopMargin, .flexibleWidth]
           text.setOutlineColor(UIColor.lightGray.withAlphaComponent(0.87), for: .normal)
           text.setOutlineColor(UIColor(hex: "#F5A623").withAlphaComponent(0.87), for: .editing)
           text.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
           text.leftViewMode = .always
           text.translatesAutoresizingMaskIntoConstraints = false
           text.heightAnchor.constraint(equalToConstant: 57).isActive = true
           return text
       }()
    
   lazy var cityTextField: MDCOutlinedTextField = {
       let text = MDCOutlinedTextField()
       text.backgroundColor = UIColor.white.withAlphaComponent(0.5)
       text.label.text = "City"
       text.setFloatingLabelColor(.black, for: .normal)
       text.setFloatingLabelColor(.black, for: .editing)
       text.setNormalLabelColor(.lightGray, for: .normal)
       text.tintColor = .lightGray
       text.font = UIFont.systemFont(ofSize: 16, weight: .medium)
       text.setTextColor(.black, for: .editing)
       text.autoresizingMask = [.flexibleBottomMargin, .flexibleTopMargin, .flexibleWidth]
       text.setTextColor(.black, for: .normal)
       text.setOutlineColor(UIColor.lightGray.withAlphaComponent(0.87), for: .normal)
       text.setOutlineColor(UIColor(hex: "#F5A623").withAlphaComponent(0.87), for: .editing)
       text.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
       text.leftViewMode = .always
       text.translatesAutoresizingMaskIntoConstraints = false
       text.heightAnchor.constraint(equalToConstant: 57).isActive = true
       return text
   }()
    
    lazy var stateTextField: MDCOutlinedTextField = {
          let text = MDCOutlinedTextField()
          text.backgroundColor = UIColor.white.withAlphaComponent(0.5)
          text.label.text = "State"
          text.setFloatingLabelColor(.black, for: .normal)
          text.setFloatingLabelColor(.black, for: .editing)
          text.setNormalLabelColor(.lightGray, for: .normal)
          text.tintColor = .lightGray
          text.font = UIFont.systemFont(ofSize: 16, weight: .medium)
          text.setTextColor(.black, for: .editing)
          text.setTextColor(.black, for: .normal)
          text.autoresizingMask = [.flexibleBottomMargin, .flexibleTopMargin, .flexibleWidth]
          text.setOutlineColor(UIColor.lightGray.withAlphaComponent(0.87), for: .normal)
          text.setOutlineColor(UIColor(hex: "#F5A623").withAlphaComponent(0.87), for: .editing)
          text.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
          text.leftViewMode = .always
          text.translatesAutoresizingMaskIntoConstraints = false
          text.heightAnchor.constraint(equalToConstant: 57).isActive = true
          return text
      }()
   
    lazy var zipCodeTextField: MDCOutlinedTextField = {
             let text = MDCOutlinedTextField()
             text.backgroundColor = UIColor.white.withAlphaComponent(0.5)
             text.label.text = "Zip code / PostCode"
             text.setFloatingLabelColor(.black, for: .normal)
             text.setFloatingLabelColor(.black, for: .editing)
             text.setNormalLabelColor(.lightGray, for: .normal)
             text.tintColor = .lightGray
             text.autoresizingMask = [.flexibleBottomMargin, .flexibleTopMargin, .flexibleWidth]
             text.font = UIFont.systemFont(ofSize: 16, weight: .medium)
             text.setTextColor(.black, for: .editing)
             text.setTextColor(.black, for: .normal)
             text.setOutlineColor(UIColor.lightGray.withAlphaComponent(0.87), for: .normal)
             text.setOutlineColor(UIColor(hex: "#F5A623").withAlphaComponent(0.87), for: .editing)
             text.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
             text.leftViewMode = .always
             text.translatesAutoresizingMaskIntoConstraints = false
             text.heightAnchor.constraint(equalToConstant: 57).isActive = true
             return text
         }()
    
    lazy var countryTextField: MDCOutlinedTextField = {
                let text = MDCOutlinedTextField()
                text.backgroundColor = UIColor.white.withAlphaComponent(0.5)
                text.label.text = "Country"
                text.setFloatingLabelColor(.black, for: .normal)
                text.setFloatingLabelColor(.black, for: .editing)
                text.setNormalLabelColor(.lightGray, for: .normal)
                text.tintColor = .lightGray
                text.autoresizingMask = [.flexibleBottomMargin, .flexibleTopMargin, .flexibleWidth]
                text.font = UIFont.systemFont(ofSize: 16, weight: .medium)
                text.setTextColor(.black, for: .editing)
                text.setTextColor(.black, for: .normal)
                text.autoresizingMask = [.flexibleBottomMargin, .flexibleTopMargin, .flexibleWidth]
                text.setOutlineColor(UIColor.lightGray.withAlphaComponent(0.87), for: .normal)
                text.setOutlineColor(UIColor(hex: "#F5A623").withAlphaComponent(0.87), for: .editing)
                text.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
                text.leftViewMode = .always
                text.translatesAutoresizingMaskIntoConstraints = false
                text.heightAnchor.constraint(equalToConstant: 57).isActive = true
                return text
            }()
    
   
    lazy var billingContinueButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("CONTINUE", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(hex: "#F5A623")
        button.layer.cornerRadius = 4
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    lazy var stackView: UIStackView = {
        let stack = UIStackView()
        stack.spacing = 8
        stack.axis = .vertical
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    lazy var firstStackView: UIStackView = {
        let stack = UIStackView()
        stack.spacing = 8
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    lazy var secondStackView: UIStackView = {
        let stack = UIStackView()
        stack.spacing = 8
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    lazy var goBackButton: UIButton = {
           let button = UIButton(type: .system)
           button.setTitle("GO BACK", for: .normal)
           button.setTitleColor(.black, for: .normal)
           button.backgroundColor = UIColor.clear
           button.layer.cornerRadius = 0
           button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
           button.translatesAutoresizingMaskIntoConstraints = false
           return button
       }()
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        addSubview(stackView)
        addSubview(billingContinueButton)
        addSubview(goBackButton)
        
        stackView.addArrangedSubview(billingAddressTextField)
        stackView.addArrangedSubview(firstStackView)
        stackView.addArrangedSubview(secondStackView)
        
        firstStackView.addArrangedSubview(cityTextField)
        firstStackView.addArrangedSubview(stateTextField)
        
        secondStackView.addArrangedSubview(zipCodeTextField)
        secondStackView.addArrangedSubview(countryTextField)
        
        setupConstraints()
    }
    
    func setupConstraints(){
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant:20),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant:35),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant:-20),
            
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 22),
            
            billingContinueButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            billingContinueButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            billingContinueButton.heightAnchor.constraint(equalToConstant: 57),
            billingContinueButton.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 42),
            
            goBackButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            goBackButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
                       goBackButton.heightAnchor.constraint(equalToConstant: 40),
                       goBackButton.topAnchor.constraint(equalTo: billingContinueButton.bottomAnchor, constant: 5)
            
        ])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
