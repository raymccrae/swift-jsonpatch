import Foundation
import CoreFoundation
func cfValue(_ a: NSArray, _ index: Int) -> AnyObject {
    let cf = unsafeBitCast(a, to: CFArray.self)
    return Unmanaged<AnyObject>.fromOpaque(CFArrayGetValueAtIndex(cf,index)).takeUnretainedValue()
}
let child = NSMutableArray(array: [1, true])
let string = NSMutableString(string: "before")
let a = NSMutableArray(objects: child, string)
for i in 0..<a.count {
 print("array", i, "normal", type(of:a[i]), "CF", type(of:cfValue(a,i)), "identity", cfValue(a,i) === (i == 0 ? child : string))
}
let d = NSMutableDictionary()
d["child"] = child
d["s"] = string
let cf = unsafeBitCast(d,to:CFDictionary.self)
for key in ["child","s"] {
 let k=key as NSString
 let ptr=CFDictionaryGetValue(cf,Unmanaged.passUnretained(k).toOpaque())!
 let obj=Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
 print("dict",key,"normal",type(of:d[key]!),"CF",type(of:obj))
}
let u = NSMutableDictionary()
u["é" as NSString] = 1
u["e\u{301}" as NSString] = 2
print("unicode",u.count,u.allKeys)
let nums:NSArray = [true, false, 1, 0, UInt64.max, Int64.min]
for i in 0..<nums.count {
 let n=nums[i]
 print("number",n,type(of:n), n is NSNumber, n is Bool)
 if let v=n as? NSNumber { print("num details",v.objCType.pointee,CFGetTypeID(v),CFBooleanGetTypeID()) }
}
for literal in ["-9223372036854775808", "9223372036854775808", "18446744073709551615"] {
 do {
 let data=Data("[{\"op\":\"add\",\"path\":\"/x\",\"value\":\(literal)}]".utf8)
 let value=try JSONSerialization.jsonObject(with:data)
 let out=try JSONSerialization.data(withJSONObject:value)
 print("numeric roundtrip",literal,String(decoding:out,as:UTF8.self))
 } catch {print("numeric failed",literal,error)}
}

for literal in ["-9223372036854775808", "-9223372036854775807", "-9007199254740993", "-9007199254740992", "-9007199254740991", "-1", "0", "1", "9007199254740991", "9007199254740992", "9007199254740993", "9223372036854775806", "9223372036854775807", "9223372036854775808", "18446744073709551614", "18446744073709551615"] {
 let data=Data("[{\"op\":\"add\",\"path\":\"/x\",\"value\":\(literal)}]".utf8)
 do { _ = try JSONDecoder().decode(JSONPatch.self,from:data); print("decode success",literal) } catch {print("decode FAIL",literal,error)}
 do {
 let patch=try JSONPatch(data:data)
 print("foundation out",literal,String(decoding:try patch.data(),as:UTF8.self))
 print("codable out",literal,String(decoding:try JSONEncoder().encode(patch),as:UTF8.self))
 } catch { print("serialize FAIL",literal,error) }
}
