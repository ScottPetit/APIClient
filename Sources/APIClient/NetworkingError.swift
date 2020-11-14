//
//  NetworkingError.swift
//  
//
//  Created by Scott Petit on 11/14/20.
//

import Foundation

public enum NetworkingError: Swift.Error {
    case foundation(NSError)
    case url(URLError)
    case decoding(DecodingError)
}
