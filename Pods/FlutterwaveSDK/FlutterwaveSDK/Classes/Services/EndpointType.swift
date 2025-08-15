//
//  EndpointType.swift
//  Alamofire
//
//  Created by Rotimi Joshua on 26/08/2020.
//


import Foundation
protocol EndpointType {

    var baseURL: URL { get }
    var stagingURL:URL{ get }

    var path: String { get }

}
