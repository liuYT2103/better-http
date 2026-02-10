extends RefCounted
class_name BetterHTTPInterceptors

var _request:Array[Callable] = []
var _response:Array[Callable] = []

func use_request(fn:Callable):
	_request.append(fn)
	
func use_response(fn:Callable):
	_response.append(fn)
	
func eject_request(fn:Callable):
	_request.erase(fn)

func eject_response(fn:Callable):
	_response.erase(fn)
