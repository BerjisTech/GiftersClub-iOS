
//
//  AccountForm.swift
//  RaveTest
//
//  Created by Olusegun Solaja on 09/09/2019.
//  Copyright © 2019 Olusegun Solaja. All rights reserved.
//

import UIKit
import MaterialComponents
class AccountForm: UIView {
    
    lazy var accountImageView: UIImageView = {
        let image = UIImageView()
        image.contentMode = .scaleAspectFit
        image.clipsToBounds = true
        image.translatesAutoresizingMaskIntoConstraints = false
        return image
    }()
    
    lazy var phoneNumberTextField: MDCOutlinedTextField = {
        let text = MDCOutlinedTextField()
        text.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        text.label.text = "Phone number"
        text.setFloatingLabelColor(.black, for: .normal)
        text.setFloatingLabelColor(.black, for: .editing)
        text.tintColor = .lightGray
        text.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        text.setTextColor(.black, for: .editing)
        text.autoresizingMask = [.flexibleBottomMargin, .flexibleTopMargin, .flexibleWidth]
        text.setTextColor(.black, for: .normal)
        text.setNormalLabelColor(.lightGray, for: .normal)
        text.setOutlineColor(UIColor.lightGray.withAlphaComponent(0.87), for: .normal)
        text.setOutlineColor(UIColor(hex: "#F5A623").withAlphaComponent(0.87), for: .editing)
        text.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        text.leftViewMode = .always
        text.translatesAutoresizingMaskIntoConstraints = false
        text.keyboardType = .numberPad
        return text
    }()

    lazy var accountNumberTextField: MDCOutlinedTextField = {
        let text = MDCOutlinedTextField()
        text.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        text.label.text = "Account number"
        text.setFloatingLabelColor(.black, for: .normal)
        text.setFloatingLabelColor(.black, for: .editing)
        text.tintColor = .lightGray
        text.autoresizingMask = [.flexibleBottomMargin, .flexibleTopMargin, .flexibleWidth]
        text.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        text.setTextColor(.black, for: .editing)
            text.setNormalLabelColor(.lightGray, for: .normal)
        text.setTextColor(UIColor.black, for: .normal)
        text.setOutlineColor(UIColor.lightGray.withAlphaComponent(0.87), for: .normal)
        text.setOutlineColor(UIColor(hex: "#F5A623").withAlphaComponent(0.87), for: .editing)
        text.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        text.leftViewMode = .always
        text.translatesAutoresizingMaskIntoConstraints = false
        text.keyboardType = .numberPad
        return text
    }()
    
    
    lazy var dobTextField: MDCOutlinedTextField = {
        let text = MDCOutlinedTextField()
        text.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        text.label.text = "DDMMYYYY"
        text.setFloatingLabelColor(.black, for: .normal)
        text.setFloatingLabelColor(.black, for: .editing)
        text.tintColor = .lightGray
        text.isHidden = true
        text.autoresizingMask = [.flexibleBottomMargin, .flexibleTopMargin, .flexibleWidth]
        text.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        text.setTextColor(.black, for: .editing)
        text.setTextColor(UIColor.black, for: .normal)
        text.setNormalLabelColor(.lightGray, for: .normal)
        text.setOutlineColor(UIColor.lightGray.withAlphaComponent(0.87), for: .normal)
        text.setOutlineColor(UIColor(hex: "#F5A623").withAlphaComponent(0.87), for: .editing)
//        text.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
//        text.leftViewMode = .always
        text.translatesAutoresizingMaskIntoConstraints = false
        text.keyboardType = .numberPad
        return text
    }()
    
    lazy var accountBvn: MDCOutlinedTextField = {
        let text = MDCOutlinedTextField()
        text.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        text.label.text = "BVN"
        text.setFloatingLabelColor(.black, for: .normal)
        text.setFloatingLabelColor(.black, for: .editing)
        text.tintColor = .lightGray
        text.isHidden = true
        text.autoresizingMask = [.flexibleBottomMargin, .flexibleTopMargin, .flexibleWidth]
        text.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        text.setTextColor(.black, for: .editing)
        text.setNormalLabelColor(.lightGray, for: .normal)
        text.setTextColor(UIColor.black, for: .normal)
        text.setOutlineColor(UIColor.lightGray.withAlphaComponent(0.87), for: .normal)
        text.setOutlineColor(UIColor(hex: "#F5A623").withAlphaComponent(0.87), for: .editing)
        text.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        text.leftViewMode = .always
        text.keyboardType = .numberPad
        text.translatesAutoresizingMaskIntoConstraints = false
        return text
    }()
    
    
    lazy var accountPayButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("PAY", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(hex: "#F5A623")
        button.layer.cornerRadius = 4
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.heightAnchor.constraint(equalToConstant: 57).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    lazy var goBack: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("GO BACK", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.layer.cornerRadius = 4
        button.heightAnchor.constraint(equalToConstant: 57).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    lazy var stackView: UIStackView = {
        let stack = UIStackView()
        stack.spacing = 14
        stack.axis = .vertical
        stack.distribution = .fillProportionally
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
       
        addSubview(accountImageView)
        addSubview(stackView)
        stackView.addArrangedSubview(phoneNumberTextField)
        stackView.addArrangedSubview(accountNumberTextField)
        stackView.addArrangedSubview(dobTextField)
        stackView.addArrangedSubview(accountBvn)
        addSubview(accountPayButton)
        addSubview(goBack)
        setupConstraints()
    }
    
    func setupConstraints(){
        NSLayoutConstraint.activate([
            
            accountImageView.topAnchor.constraint(equalTo: topAnchor, constant:20),
            accountImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            accountImageView.heightAnchor.constraint(equalToConstant: 44),
            accountImageView.widthAnchor.constraint(equalToConstant: 129),
            
            
            stackView.topAnchor.constraint(equalTo: accountImageView.bottomAnchor, constant: 18),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant:20),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant:-20),
            
            accountPayButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            accountPayButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            accountPayButton.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 19),
            accountPayButton.heightAnchor.constraint(equalToConstant: 50),
            
            goBack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            goBack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            goBack.topAnchor.constraint(equalTo: accountPayButton.bottomAnchor, constant: 8),
            //goBack.heightAnchor.constraint(equalToConstant: 50),
            
        ])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
