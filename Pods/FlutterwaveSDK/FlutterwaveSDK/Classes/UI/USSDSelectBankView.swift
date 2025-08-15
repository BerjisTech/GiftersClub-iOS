//
//  USSDSelectBankView.swift
//  RaveSDK
//
//  Created by Rotimi Joshua on 02/09/2020.
//

import UIKit
import MaterialComponents
class USSDSelectBankView: UIView {
    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Please select your bank"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        return label
    }()
    
    
    let arrowButtons: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "rave_down_arrow",in: Bundle.getResourcesBundle(), compatibleWith: nil), for: .normal)
        button.tintColor = UIColor(hex: "#647482")
        button.widthAnchor.constraint(equalToConstant: 20).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    lazy var otherBanksTextField: MDCOutlinedTextField = {
        let text = MDCOutlinedTextField()
        text.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        text.label.text = "Select a Bank"
        text.setFloatingLabelColor(.black, for: .normal)
        text.setFloatingLabelColor(.black, for: .editing)
        text.tintColor = .blue
        text.setNormalLabelColor(.lightGray, for: .normal)
        text.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        text.setTextColor(.black, for: .editing)
        text.setTextColor(.black, for: .normal)
        text.setOutlineColor(UIColor.lightGray.withAlphaComponent(0.87), for: .normal)
        text.setOutlineColor(UIColor(hex: "#F5A623").withAlphaComponent(0.87), for: .editing)
        let redView = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        redView.addSubview(arrowButtons)
        text.rightView = redView
        text.rightViewMode = .always
        text.translatesAutoresizingMaskIntoConstraints = false
        return text
    }()
    
    
    lazy var PayButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("PAY", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(hex: "#F5A623")
        button.layer.cornerRadius = 4
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        button.heightAnchor.constraint(equalToConstant: 57).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    
    lazy var anotherPaymentButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Choose another payment method", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.backgroundColor = UIColor.clear
        button.layer.cornerRadius = 0
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        addSubview(otherBanksTextField)
        addSubview(PayButton)
        
        setupConstraints()
    }
    
    func setupConstraints(){
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant:20),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant:20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant:-20),
            titleLabel.heightAnchor.constraint(equalToConstant: 55),
            
            otherBanksTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            otherBanksTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            otherBanksTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 35),
            otherBanksTextField.heightAnchor.constraint(equalToConstant: 57),
            
            PayButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            PayButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            PayButton.topAnchor.constraint(equalTo: otherBanksTextField.bottomAnchor, constant: 35),
            PayButton.heightAnchor.constraint(equalToConstant: 57),
            
            
        ])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

