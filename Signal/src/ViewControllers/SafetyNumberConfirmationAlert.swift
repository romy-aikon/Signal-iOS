//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

class SafetyNumberConfirmationAlert: NSObject {

    let TAG = "[SafetyNumberConfirmationAlert]"

    private let contactsManager: OWSContactsManager
    private let storageManager: TSStorageManager

    init(contactsManager: OWSContactsManager) {
        self.contactsManager = contactsManager
        self.storageManager = TSStorageManager.shared()
    }

    public class func presentAlertIfNecessary(fromViewController: UIViewController, recipientId: String, confirmationText: String, contactsManager: OWSContactsManager, completion: @escaping (Bool) -> Void) -> Bool {
        return self.presentAlertIfNecessary(fromViewController: fromViewController, recipientIds: [recipientId], confirmationText: confirmationText, contactsManager: contactsManager, completion: completion)
    }

    public class func presentAlertIfNecessary(fromViewController: UIViewController, recipientIds: [String], confirmationText: String, contactsManager: OWSContactsManager, completion: @escaping (Bool) -> Void) -> Bool {
        return SafetyNumberConfirmationAlert(contactsManager: contactsManager).presentIfNecessary(fromViewController: fromViewController,
                                                                                                  recipientIds: recipientIds,
                                                                                                  confirmationText: confirmationText,
                                                                                                  completion: completion)
    }

    /**
     * Shows confirmation dialog if at least one of the recipient id's is not confirmed.
     *
     * @returns true  if an alert was shown
     *          false if there were no unconfirmed identities
     */
    public func presentIfNecessary(fromViewController: UIViewController, recipientIds: [String], confirmationText: String, completion: @escaping (Bool) -> Void) -> Bool {

        guard let unconfirmedIdentity = self.unconfirmedIdentityThatShouldBlockSending(recipientIds: recipientIds) else {
            // No identities to confirm, no alert to present.
            return false
        }

        let displayName: String = {
            if let signalAccount = contactsManager.signalAccountMap[unconfirmedIdentity.recipientId] {
                return contactsManager.displayName(for: signalAccount)
            } else {
                return contactsManager.displayName(forPhoneIdentifier: unconfirmedIdentity.recipientId)
            }
        }()

        let titleFormat = NSLocalizedString("CONFIRM_SENDING_TO_CHANGED_IDENTITY_TITLE_FORMAT",
                                            comment: "Action sheet title presented when a users's SN have recently changed. Embeds {{contact's name or phone number}}")
        let title = String(format: titleFormat, displayName)

        let bodyFormat = NSLocalizedString("CONFIRM_SENDING_TO_CHANGED_IDENTITY_BODY_FORMAT",
                                           comment: "Action sheet body presented when a user's SN have recently changed. Embeds {{contact's name or phone nubmer}}")
        let body = String(format: bodyFormat, displayName)

        let actionSheetController = UIAlertController(title: title, message:body, preferredStyle: .actionSheet)

        let confirmAction = UIAlertAction(title: confirmationText, style: .default) { _ in
            Logger.info("\(self.TAG) Confirmed identity: \(unconfirmedIdentity)")
            OWSDispatch.sessionStoreQueue().async {
                self.storageManager.saveRemoteIdentity(unconfirmedIdentity.identityKey,
                                                       recipientId: unconfirmedIdentity.recipientId,
                                                       approvedForBlockingUse: true,
                                                       approvedForNonBlockingUse: true)
                DispatchQueue.main.async {
                    completion(true)
                }
            }
        }
        actionSheetController.addAction(confirmAction)

        let showSafetyNumberAction = UIAlertAction(title: NSLocalizedString("VERIFY_PRIVACY", comment: "Action sheet item"), style: .default) { _ in
            Logger.info("\(self.TAG) Opted to show Safety Number for identity: \(unconfirmedIdentity)")

            self.presentSafetyNumberViewController(fromViewController: fromViewController,
                                                   theirIdentityKey: unconfirmedIdentity.identityKey,
                                                   theirRecipientId: unconfirmedIdentity.recipientId,
                                                   theirDisplayName: displayName,
                                                   completion: { completion(false) })

        }
        actionSheetController.addAction(showSafetyNumberAction)

        let dismissAction = UIAlertAction(title: NSLocalizedString("TXT_CANCEL_TITLE", comment: "generic cancel text"), style: .cancel)
        actionSheetController.addAction(dismissAction)

        fromViewController.present(actionSheetController, animated: true)
        return true
    }

    public func presentSafetyNumberViewController(fromViewController: UIViewController, theirIdentityKey: Data, theirRecipientId: String, theirDisplayName: String, completion: (() -> Void)? = nil) {
        let fingerprintViewController = UIStoryboard.instantiateFingerprintViewController()

        let fingerprintBuilder = OWSFingerprintBuilder(storageManager: self.storageManager, contactsManager: self.contactsManager)
        let fingerprint = fingerprintBuilder.fingerprint(withTheirSignalId: theirRecipientId, theirIdentityKey: theirIdentityKey)

        fingerprintViewController.configure(fingerprint: fingerprint, contactName: theirDisplayName)

        fromViewController.present(fingerprintViewController, animated: true, completion: completion)
    }

    private func unconfirmedIdentitiesThatShouldBlockSending(recipientIds: [String]) -> [OWSRecipientIdentity] {
        return recipientIds.flatMap {
            return self.storageManager.unconfirmedIdentityThatShouldBlockSending(forRecipientId: $0)
        }
    }

    private func unconfirmedIdentityThatShouldBlockSending(recipientIds: [String]) -> OWSRecipientIdentity? {
        return unconfirmedIdentitiesThatShouldBlockSending(recipientIds: recipientIds).first
    }

    private func shouldShow(recipientIds: [String]) -> Bool {
        return !unconfirmedIdentitiesThatShouldBlockSending(recipientIds: recipientIds).isEmpty
    }

}
