//
//  RegistrationKey.swift
//  Parade
//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// Compatibility of concrete views, independently of presenter or item identity.
struct RegistrationKey: Hashable {
    let viewType: ObjectIdentifier
    let elementKind: String?

    init<View: UICollectionReusableView>(viewType: View.Type, elementKind: String? = nil) {
        self.viewType = ObjectIdentifier(viewType)
        self.elementKind = elementKind
    }
}
