//
//  TeslaSwift.swift
//  TeslaSwift
//
//  Created by Joao Nunes on 04/03/16.
//  Copyright © 2016 Joao Nunes. All rights reserved.
//

import Foundation
import ObjectMapper
import BrightFutures
import Alamofire

public enum RoofState:String {
	case Open		= "open"
	case Close		= "close"
	case Comfort	= "comfort"
	case Vent		= "vent"
	case Move		= "move"
}

public enum VehicleCommand {
	case WakeUp
	case ValetMode(options:ValetCommandOptions)
	case ResetValetPin
	case OpenChargeDoor
	case ChargeLimitStandard
	case ChargeLimitMaxRange
	case ChargeLimitPercentage(limit:Int)
	case StartCharging
	case StopCharging
	case FlashLights
	case HonkHorn
	case UnlockDoors
	case LockDoors
	case SetTemperature(driverTemperature:Double, passangerTemperature:Double)
	case StartAutoConditioning
	case StopAutoConditioning
	case SetSunRoof(state:RoofState, percentage:Double)
	case StartVehicle(password:String)
	case OpenTrunk(options:OpenTrunkOptions)
	
	func path() -> String {
		switch self {
		case .WakeUp:
			return "wake_up"
		case .ValetMode:
			return "command/set_valet_mode"
		case .ResetValetPin:
			return "command/reset_valet_pin"
		case .OpenChargeDoor:
			return "command/charge_port_door_open"
		case .ChargeLimitStandard:
			return "command/charge_standard"
		case .ChargeLimitMaxRange:
			return "command/charge_max_range"
		case let .ChargeLimitPercentage(limit):
			return  "command/set_charge_limit?percent=\(limit)"
		case .StartCharging:
			return  "command/charge_start"
		case .StopCharging:
			return "command/charge_stop"
		case .FlashLights:
			return "command/flash_lights"
		case .HonkHorn:
			return "command/honk_horn"
		case .UnlockDoors:
			return "command/door_unlock"
		case .LockDoors:
			return "command/door_lock"
		case let .SetTemperature(driverTemperature, passangerTemperature):
			return "command/set_temps?driver_temp=\(driverTemperature)&passenger_temp=\(passangerTemperature)"
		case .StartAutoConditioning:
			return "command/auto_conditioning_start"
		case .StopAutoConditioning:
			return "command/auto_conditioning_stop"
		case let .SetSunRoof(state, percentage):
			return "command/sun_roof_control?state=\(state.rawValue)&percent=\(percentage)"
		case let .StartVehicle(password):
			return "command/remote_start_drive?password=\(password)"
		case .OpenTrunk:
			return "command/trunk_open"
		}
	}
}

public enum TeslaError:ErrorType {
	case NetworkError(error:NSError)
	case AuthenticationRequired
	case InvalidOptionsForCommand
}



public class TeslaSwift {
	
	public static let defaultInstance = TeslaSwift()
	public var useMockServer = false
	public var debuggingEnabled = false
	
	var token:AuthToken?
	
	private var email:String?
	private var password:String?
}

extension TeslaSwift {
	
	
	public var isAuthenticated:Bool {
		return token != nil
	}
	
	/**
	Performs the authentition with the Tesla API
	
	You only need to call this once. The token will be stored and your credentials.
	If the token expires your credentials will be reused.
	
	- parameter email:      The email address.
	- parameter password:   The password.
	
	- returns: A Future with the AuthToken.
	*/

	public func authenticate(email:String, password:String) -> Future<AuthToken,TeslaError> {
		
		self.email = email
		self.password = password

		let body = AuthTokenRequest()
		body.email = email
		body.password = password
		body.grantType = "password"
		body.clientSecret = "c75f14bbadc8bee3a7594412c31416f8300256d7668ea7e6e7f06727bfb9d220"
		body.clientID = "e4a9949fcfa04068f59abb5a658f2bac0a3428e4652315490b659d5ab3f35a9e"
		
		return request(.Authentication, body: body)
			.andThen { (result) -> Void in
			self.token = result.value
		}
		
	}
	
	/**
	Fetchs the list of your vehicles including not yet delivered ones
	
	- returns: A Future with an array of Vehicles.
	*/
	public func getVehicles() -> Future<[Vehicle],TeslaError> {
		
		return checkAuthentication().flatMap { (token) -> Future<[Vehicle], TeslaError> in
			self.request(.Vehicles, body: nil, keyPath: "response")
		}
		
	}
	
	/**
	Fetchs the vehicle status
	
	- returns: A Future with VehicleDetails object containing all the possible status information.
	*/
	public func getVehicleStatus(vehicle:Vehicle) -> Future<VehicleDetails,TeslaError> {
		
		return checkAuthentication().flatMap {
			(token) -> Future<(((((AnyObject,ChargeState),ClimateState),DriveState),GuiSettings),VehicleState), TeslaError> in
			
			let vehicleID = vehicle.vehicleID!
			
			return self.request(.MobileAccess(vehicleID: vehicleID),body: nil)
				.zip(self.request(.ChargeState(vehicleID: vehicleID), body: nil, keyPath: "response"))
				.zip(self.request(.ClimateState(vehicleID: vehicleID), body: nil, keyPath: "response"))
				.zip(self.request(.DriveState(vehicleID: vehicleID), body: nil, keyPath: "response"))
				.zip(self.request(.GuiSettings(vehicleID: vehicleID), body: nil, keyPath: "response"))
				.zip(self.request(.VehicleState(vehicleID: vehicleID), body: nil, keyPath: "response"))
			
			}.flatMap {
				(result:((((mobileAccess:AnyObject, chargeState:ChargeState), climateState:ClimateState), driveState:DriveState), guiSettings:GuiSettings), vehicleState:VehicleState) -> Future<VehicleDetails, TeslaError> in
			
		
				let vehicleDetails = VehicleDetails()
				vehicleDetails.mobileAccess = (result.0.0.0.mobileAccess as! [String:Bool])["response"]
				vehicleDetails.chargeState = result.0.0.0.chargeState
				vehicleDetails.climateState = result.0.0.climateState
				vehicleDetails.driveState = result.0.driveState
				vehicleDetails.guiSettings = result.guiSettings
				vehicleDetails.vehicleState = vehicleState
				return Future<VehicleDetails,TeslaError>(value: vehicleDetails)
				
		}
		
	}
	
	
	/**
	Sends a command to the vehicle
	
	- parameter vehicle: the vehicle that will receive the command
	- parameter command: the command to send to the vehicle
	- returns: A Future with the CommandResponse object containing the results of the command.
	*/
	public func sendCommandToVehicle(vehicle:Vehicle, command:VehicleCommand) -> Future<CommandResponse,TeslaError> {
		
		var body:Mappable?
		
		switch command {
		case let .ValetMode(options):
			body = options
		case let .OpenTrunk(options):
			body = options
		default: break
		}
		
		return checkAuthentication().flatMap { (token) -> Future<CommandResponse, TeslaError> in
			self.request(.Command(vehicleID: vehicle.vehicleID!, command: command), body: body, keyPath: "response")
		}
		
	}
}

extension TeslaSwift {
	
	func checkToken() -> Future<Bool,TeslaError> {
		
		if let token = self.token {
			return Future<Bool,TeslaError>(value: token.isValid)
		} else {
			return Future<Bool,TeslaError>(value:false)
		}
	}
	
	func checkAuthentication() -> Future<AuthToken,TeslaError> {
		
		return checkToken().flatMap { (value) -> Future<AuthToken, TeslaError> in
			
			if (value) {
				return Future<AuthToken, TeslaError>(value: self.token!)
			} else {
				if let email = self.email, password = self.password {
					return self.authenticate(email, password: password)
				} else {
					return Future<AuthToken, TeslaError>(error: .AuthenticationRequired)
				}
				
			}
		}
	}
	
	func request<T:Mappable>(endpoint:Endpoint, body:Mappable?, keyPath:String? = nil) -> Future<T,TeslaError> {
		
		return prepareRequest(endpoint, body: body).responseObjectFuture(keyPath, logging: debuggingEnabled)
	}
	func request<T:Mappable>(endpoint:Endpoint, body:Mappable?, keyPath:String? = nil) -> Future<[T],TeslaError> {
		
		return prepareRequest(endpoint, body: body).responseObjectFuture(keyPath, logging: debuggingEnabled)
	}
	func request(endpoint:Endpoint, body:Mappable?) -> Future<AnyObject,TeslaError> {
		
		return prepareRequest(endpoint, body: body).responseObjectFuture(debuggingEnabled)
	}
	
	func prepareRequest(endpoint:Endpoint, body:Mappable?) -> Request {
		
		let request = NSMutableURLRequest(URL: NSURL(string: endpoint.baseURL(useMockServer).stringByAppendingString(endpoint.path))!)
		request.HTTPMethod = endpoint.method.rawValue
		
		if let token = self.token?.accessToken {
			request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		}
		
		if let body = body {
			let jsonObject = body.toJSON()
			request.HTTPBody = try? NSJSONSerialization.dataWithJSONObject(jsonObject, options: [])
			request.setValue("application/json", forHTTPHeaderField: "content-type")
		}
		let alamonfireRequest = Alamofire.request(request)
		
		logDebug("Request: \(alamonfireRequest)", debuggingEnabled: debuggingEnabled)
		if let body = body {
			logDebug("Request Body: \(body.toJSONString(true)!)", debuggingEnabled: debuggingEnabled)
		}
		
		return alamonfireRequest
	}
	
}

func logDebug(format: String, debuggingEnabled: Bool) {
	if debuggingEnabled {
		NSLog(format)
	}
}
