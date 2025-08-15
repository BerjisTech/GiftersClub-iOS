//
//  SABankAccountView.swift
//  RaveSDK
//
//  Created by Rotimi Joshua on 14/09/2020.
//

import UIKit

class SABankAccountView: UIView {
    
    lazy var amountLabel: UILabel = {
        let label = UILabel()
        label.text = "You are paying"
        label.textColor = UIColor(hex: "#808080")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        return label
    }()
   
    lazy var payButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("PAY", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(hex: "#F5A623")
        button.layer.cornerRadius = 4
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        button.heightAnchor.constraint(equalToConstant: 57).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    
    override init(frame: CGRect) {
         super.init(frame: frame)
         addSubview(payButton)
    
         setupConstraints()
     }
   
    
    func setupConstraints(){
        NSLayoutConstraint.activate([
            
            amountLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            amountLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            amountLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            amountLabel.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 0),
          
            payButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            payButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            payButton.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 0),
            payButton.topAnchor.constraint(equalTo: amountLabel.bottomAnchor, constant: 20),
            payButton.heightAnchor.constraint(equalToConstant: 50),
          
            
        ])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
