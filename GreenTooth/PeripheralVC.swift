//
//  PeripheralVC.swift
//  GreenTooth
//
//  Created by Nicolas Rizk on 11/28/16.
//  Copyright © 2016 Nicolas Rizk. All rights reserved.
//

import UIKit
import CoreBluetooth

class PeripheralVC: UIViewController {
  
  @IBOutlet weak var textView: UITextView!
  
  var peripheralManager : CBPeripheralManager!
  var transferCharacteristic : CBMutableCharacteristic!
  var dataToSend : NSData!
  var sendDataIndex : Int!

  override func viewDidLoad() {
    super.viewDidLoad()
    
    peripheralManager = CBPeripheralManager.init(delegate: self, queue: nil)
  }
  
  @IBAction func sendOverBluetooth(_ sender: UIButton) {
    toggleAdvertisement(on: true)
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    toggleAdvertisement(on: false)
  }
}

extension PeripheralVC: CBPeripheralManagerDelegate {
  
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    
    if peripheral.state != .poweredOn { return }
    
    print("Peripheral Manager powered on")
    
    transferCharacteristic = CBMutableCharacteristic.init(
      type: CBUUID.init(string: TransferCharacteristic.UUID),
      properties: .notify,
      value: nil,
      permissions: .readable
    )
    
    let transferService = CBMutableService.init(type: CBUUID.init(string: TransferService.UUID), primary: true)
    
    transferService.characteristics = [transferCharacteristic]
    
    peripheralManager.add(transferService)
    
  }
  
  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
    print("Central subscribed to characteristic")
    
    //Get the data
    let string = textView.text!
    dataToSend = string.data(using: .utf8) as NSData!
    
    // Reset the index
    sendDataIndex = 0
    
    sendData()
  }
  
  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
    print("Central unsubscribed from characteristic")
  }
  
  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    sendData()
  }
  
  // Sends the next amount of data to the connected central
  func sendData() {
    // First up, check if we're meant to be sending an EOM
    struct Sending { static var EOM = false }
    
    if Sending.EOM {
      // send it
      let didSend = peripheralManager.updateValue("EOM".data(using: .utf8)!, for: transferCharacteristic, onSubscribedCentrals: nil)
      // Did it send?
      if didSend {
        // It did, so mark it as sent
        Sending.EOM = false
        print("Sent: EOM")
      }
      // It didn't send, so we'll exit and wait for peripheralManagerIsReadyToUpdateSubscribers to call sendData again
      return
    }
    // We're not sending an EOM, so we're sending data
    // Is there any left to send?
    if sendDataIndex >= dataToSend.length {
      // No data left.  Do nothing
      return
    }
    // There's data left, so send until the callback fails, or we're done.
    var didSend = true
    while didSend {
      // Make the next chunk
      // Work out how big it should be
      var amountToSend = dataToSend.length - sendDataIndex
      // Can't be longer than 20 bytes
      if amountToSend > 20 {
        amountToSend = 20
      }
      // Copy out the data we want
      let chunk = NSData(bytes: dataToSend.bytes + sendDataIndex, length: amountToSend)
      // Send it
      didSend = peripheralManager.updateValue(chunk as Data, for: transferCharacteristic, onSubscribedCentrals: nil)
      // If it didn't work, drop out and wait for the callback
      if !didSend {
        return
      }
      let stringFromData = String.init(data: chunk as Data, encoding: .utf8)
      
      print("Sent: \(stringFromData)")
      // It did send, so update our index
      sendDataIndex = sendDataIndex + amountToSend
      // Was it the last one?
      if sendDataIndex >= dataToSend.length {
        // It was - send an EOM
        // Set this so if the send fails, we'll send it next time
        Sending.EOM = true
        // Send it
        let eomSent = peripheralManager.updateValue("EOM".data(using: String.Encoding.utf8)!, for: transferCharacteristic, onSubscribedCentrals: nil)
        if eomSent {
          // It sent, we're all done
          Sending.EOM = false
          print("Sent: EOM")
        }
        return
      }
    }
  }
  
  func toggleAdvertisement(on: Bool) {
    if on {
      peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [CBUUID.init(string: TransferService.UUID)]])
    } else {
      peripheralManager.stopAdvertising()
    }
  }
  
}
