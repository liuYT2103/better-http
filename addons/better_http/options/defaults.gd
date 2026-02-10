extends RefCounted
class_name BetterHTTPDefaults

var base_url:String = "" ## BaseURL
var headers:= BetterHTTPDefaultHeaders.new() ## common get post put delete
var timeout:float = 6.0 ## s
