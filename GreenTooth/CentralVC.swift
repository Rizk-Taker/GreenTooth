//
//  CentralVC.swift
//  GreenTooth
//
//  Created by Nicolas Rizk on 11/28/16.
//  Copyright © 2016 Nicolas Rizk. All rights reserved.
//

import UIKit
import CoreBluetooth

class CentralVC: UIViewController {
  
  @IBOutlet weak var textView: UITextView!
  var centralManager : CBCentralManager!
  var discoveredPeripheral : CBPeripheral?
  var data : NSMutableData!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    centralManager = CBCentralManager.init(delegate: self, queue: nil)
    data = NSMutableData()
  }

}

extension CentralVC : CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state != .poweredOn {
      return
    }
    scan()
  }
  
  func scan() {
    centralManager.scanForPeripherals(withServices: [CBUUID.init(string: TransferService.UUID)], options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
    
    print("Scanning Started")
  }
  
  /** This callback comes whenever a peripheral that is advertising the TRANSFER_SERVICE_UUID is discovered.
   *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
   *  we start the connection process
   */
  
  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    
    // Reject any where the value is above reasonable range
//    if RSSI.intValue > -15 {
//      return
//    }
//    
//    // Reject if the signal strength is too low to be close enough (Close is around -22dB)
//    if RSSI.intValue < -35 {
//      return
//    }
    
    print("Discovered peripheral \(peripheral.name) at RSSI \(RSSI)")
    
    // Ok, it's in range - have we already seen it?
    if discoveredPeripheral != peripheral {
      discoveredPeripheral = peripheral
      
      // Now we connect
      centralManager.connect(peripheral, options: nil)
    
    }
  }
  
  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    print("Failed to connected to peripheral \(peripheral) with error: \(error?.localizedDescription)")
    cleanup()
  }
  
  /** We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
   */
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("Peripheral connected to central manager")
    centralManager.stopScan()
    print("Scanning Stopped")
    
    // Clear the data that we may already have
    data.setData(Data())
    
    // Set delegate to receive discovery callbacks
    peripheral.delegate = self
    
    // Search only for services that match our UUID
    peripheral.discoverServices([CBUUID.init(string: TransferService.UUID)])
  }

}

extension CentralVC: CBPeripheralDelegate {
  /** The Transfer Service was discovered
   */
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    
    if let error = error {
      print("Peripheral error discovering services \(error.localizedDescription)")
      cleanup()
      return
    }
    
    // Discover the characteristic we want...
    
    // Loop through the newly filled peripheral.services array, just in case there's more than one.
    if let services = peripheral.services {
      for service in services {
        peripheral.discoverCharacteristics([CBUUID.init(string: TransferCharacteristic.UUID)], for: service)
      }
    }
  }
  
  /** The Transfer characteristic was discovered.
   *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
   */
  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    
    if let error = error {
      print("Peripheral error discovering characteristics for service \(service) error: \(error.localizedDescription)")
      cleanup()
      return
    }
    
    if let characteristics = service.characteristics {
      for characteristic in characteristics {
        if characteristic.uuid == CBUUID.init(string: TransferCharacteristic.UUID) {
          peripheral.setNotifyValue(true, for: characteristic)
        }
      }
    }
    
  }
  
  /** This callback lets us know more data has arrived via notification on the characteristic
   */
  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    if let error = error {
      print("Peripheral error updating value for characteristic \(characteristic) error: \(error.localizedDescription)")
      return
    }
    
    let stringFromData = String.init(data: characteristic.value!, encoding: .utf8)

    if stringFromData == "EOM" {
      let string = String.init(data: data! as Data, encoding: .utf8)
      textView.text = string
      peripheral.setNotifyValue(false, for: characteristic)
    }
  }
  
  /** The peripheral letting us know whether our subscribe/unsubscribe happened or not
   */
  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    if let error = error {
      print("Peripheral error updating notification state for characteristic \(characteristic) error: \(error.localizedDescription)")
      return
    }
    
    // Exit if it's not the transfer characteristic
    if characteristic.uuid != CBUUID.init(string: TransferCharacteristic.UUID) {
      return
    }
    
    // Notification has started
    if characteristic.isNotifying {
      print("Notification began on \(characteristic)")
    } else {
      print("Notification stopped on \(characteristic)")
      centralManager.cancelPeripheralConnection(peripheral)
    }
  }
  
  /** Once the disconnection happens, we need to clean up our local copy of the peripheral
   */
  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
   print("Peripheral is disconnected")
    discoveredPeripheral = nil
    
    // We're disconnected so time to start scanning again
    scan()
  }
  
  /** Call this when things either go wrong, or you're done with the connection.
   *  This cancels any subscriptions if there are any, or straight disconnects if not.
   *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
   */
  func cleanup() {
    if discoveredPeripheral?.state != .connected {
      return
    }
    
    if let services = discoveredPeripheral?.services {
      for service in services {
        if let characteristics = service.characteristics {
          for characteristic in characteristics {
            if characteristic.isNotifying {
              
              // It is notifying, so unsubscribe
              discoveredPeripheral?.setNotifyValue(false, for: characteristic)
              
              // And we're done
              return
            }
          }
        }
      }
    }
    
    if let peripheral = discoveredPeripheral {
      centralManager.cancelPeripheralConnection(peripheral)
    }
  }
  
}


