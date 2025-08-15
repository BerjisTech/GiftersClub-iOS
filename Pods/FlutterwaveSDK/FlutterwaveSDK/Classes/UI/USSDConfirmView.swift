//
//  USSDView.swift
//  RaveSDK
//
//  Created by Rotimi Joshua on 02/09/2020.
//

import UIKit

class USSDConfirmView: UIView {
    
    lazy var ussdInfoTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Dial the code below to complete the payment"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        return label
    }()
    
    lazy var ussdCodeLabel: UILabel = {
        let label = UILabel()
        label.text = "test"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        return label
    }()
    
    
    
    lazy var upperLineView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(hex: "#F5A623").withAlphaComponent(0.4)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    lazy var underLineView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(hex: "#F5A623").withAlphaComponent(0.4)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    
    lazy var referenceCodeLabel: UILabel = {
        let label = UILabel()
        label.text = "Reference Code"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 18, weight: .regular)
        return label
    }()
    
    
    lazy var copyButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "rave_copy_icon",in: Bundle.getResourcesBundle(), compatibleWith: nil), for: .normal)
        button.tintColor = UIColor(hex: "#647482")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
        
    }()
    

    
    lazy var anotherBankButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("CHOOSE ANOTHER BANK", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.backgroundColor = UIColor.clear
        button.layer.cornerRadius = 0
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
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
    
    
    lazy var completePayment: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("I HAVE COMPLETED THIS PAYMENT", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(hex: "#F5A623")
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 4
        button.heightAnchor.constraint(equalToConstant: 57).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(ussdInfoTitleLabel)
        addSubview(ussdCodeLabel)
        addSubview(upperLineView)
        addSubview(referenceCodeLabel)
        addSubview(underLineView)
        addSubview(copyButton)
        addSubview(completePayment)
//        addSubview(anotherBankButton)
        addSubview(goBackButton)
        
        setupConstraints()
    }
    
    func setupConstraints(){
        NSLayoutConstraint.activate([
            ussdInfoTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant:20),
            ussdInfoTitleLabel.topAnchor.constraint(equalTo: topAnchor, constant:20),
            ussdInfoTitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant:-20),
            
            
            ussdCodeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant:20),
            ussdCodeLabel.topAnchor.constraint(equalTo: ussdInfoTitleLabel.bottomAnchor, constant:30),
            ussdCodeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant:-20),
            
            upperLineView.leadingAnchor.constraint(equalTo: leadingAnchor, constant:30),
            upperLineView.topAnchor.constraint(equalTo: ussdCodeLabel.bottomAnchor, constant:30),
            upperLineView.trailingAnchor.constraint(equalTo: trailingAnchor, constant:-30),
            upperLineView.heightAnchor.constraint(equalToConstant: 1),
            
            referenceCodeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant:40),
            referenceCodeLabel.topAnchor.constraint(equalTo: upperLineView.bottomAnchor, constant:20),
            referenceCodeLabel.heightAnchor.constraint(equalToConstant: 20),
            
             copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30),
             copyButton.topAnchor.constraint(equalTo: upperLineView.topAnchor, constant:22),
             copyButton.widthAnchor.constraint(equalToConstant: 20),
             copyButton.heightAnchor.constraint(equalToConstant: 20),
            
            
            underLineView.leadingAnchor.constraint(equalTo: leadingAnchor, constant:30),
            underLineView.topAnchor.constraint(equalTo: referenceCodeLabel.bottomAnchor, constant:20),
            underLineView.trailingAnchor.constraint(equalTo: trailingAnchor, constant:-30),
            underLineView.heightAnchor.constraint(equalToConstant: 1),
            
            completePayment.leadingAnchor.constraint(equalTo: leadingAnchor, constant:20),
            completePayment.topAnchor.constraint(equalTo: underLineView.bottomAnchor, constant:40),
            completePayment.trailingAnchor.constraint(equalTo: trailingAnchor, constant:-20),
            completePayment.heightAnchor.constraint(equalToConstant: 50),
            
            goBackButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            goBackButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            goBackButton.topAnchor.constraint(equalTo: completePayment.bottomAnchor, constant: 40),
            
        ])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
