
Strict

Module Prime.NPAPI
ModuleInfo "Author: Kevin Primm"
ModuleInfo "License: MIT"
ModuleInfo "LD_OPTS: --exclude-all-symbols --enable-stdcall-fixup"

Import BRL.FileSystem
Import BRL.TextStream
Import BRL.RamStream
Import BRL.System
Import BRL.Reflection
Import BRL.Map
Import PUB.Win32
Import BRL.Threads
Import "glue.c"

?Win32
Incbin "npapi.rc"
?

Const URLNOTIFY_DONE  = 0
Const URLNOTIFY_ERR   = 1
Const URLNOTIFY_BREAK = 2

Global EVENT_URLNOTIFY = AllocUserEventId()
Global EVENT_STREAMASFILE = AllocUserEventId()

Extern
	Function _npapi_set_string(v:Byte Ptr, text:Byte Ptr, length)
	Function _npapi_get_string:Byte Ptr(v:Byte Ptr)
	Function _npapi_get_url_notify(instance:Byte Ptr, url:Byte Ptr, target:Byte Ptr, data:Byte Ptr)
	Function _npapi_post_url_notify(instance:Byte Ptr, url:Byte Ptr, target:Byte Ptr, length:Long, buf:Byte Ptr, file, notifyData:Byte Ptr)
	Function _npapi_get_page_url:Byte Ptr(instance:Byte Ptr)
End Extern

Type TNPAPIStream
	Field _ptr:Byte Ptr, _link:TLink
End Type

Type TNPAPIObject
	Global _methodmap:TMap = New TMap, _hwndmap:TMap = New TMap
	Field _hwnd, _result:Byte Ptr
	Field _instance:Byte Ptr, _scriptobject:Byte Ptr
	Field _wndproc:Byte Ptr
	Field _streams:TList = New TList
	
	Method Initialize(args:TMap) ; End Method
	Method Scriptable() ; End Method
	Method InvokeDefault() ; End Method
	Method Destroy() ; End Method
	Method OnEvent( event:TEvent ) ; End Method
	
	?Threaded
	Field _thread:TThread, _mutex:TMutex = CreateMutex()
	
	Method Thread:Object() ; End Method

	Method EmitEvent(event:TEvent)
		Return brl.event.EmitEvent(event)
	End Method
	
	Function ThreadFunc:Object( data:Object )
		Return TNPAPIObject(data).Thread()
	End Function
	
	Method New()
		_thread = CreateThread(ThreadFunc, Self)
	End Method

	?
	
	Method GetUrlNotify(url$, target$ = "", notifyData:Object = Null)
		Local u:Byte Ptr = url.ToCString(), t:Byte Ptr = Null, d:Byte Ptr = Null
		If target.length <> 0 t = target.ToCString()
		If notifyData d = Byte Ptr(notifyData) - 8 
		_npapi_get_url_notify(_instance, u, t, d)
		MemFree u
		MemFree t
	End Method
	
	Method PostUrlNotify(url$, target$, buf:Object, notifyData:Object = Null)
		Local u:Byte Ptr = url.ToCString(), t:Byte Ptr = Null, d:Byte Ptr = Null
		If target.length <> 0 t = target.ToCString()
		Local b:Byte Ptr = String(buf).ToCString()
		If notifyData d = Byte Ptr(notifyData) - 8 
		_npapi_post_url_notify(_instance,u,t, String(buf).length + 1, b, False, d)
		MemFree u
		MemFree t
		MemFree b
	End Method
	
	Method PageUrl$()
		Return String.FromCString(_npapi_get_page_url(_instance))
	End Method
	
	Method NPVoid()
		Int Ptr(_result + 0)[0] = 0
		Return True
	End Method
	
	Method NPNull()
		Int Ptr(_result + 0)[0] = 1
		Return True
	End Method
	
	Method NPBool(bool)
		Int Ptr(_result + 0)[0] = 2
		Int Ptr(_result + 8)[0] = (bool <> 0)
		Return True
	End Method

	Method NPInt(integer)
		Int Ptr(_result + 0)[0] = 3
		Int Ptr(_result + 8)[0] = integer
		Return True
	End Method
		
	Method NPDouble(d!)
		Int Ptr(_result + 0)[0] = 4
		Double Ptr(_result + 8)[0] = d
		Return True
	End Method
	
	Method NPString(str$)
		Local txt:Byte Ptr = str.ToCString()
		_npapi_set_string _result, txt, str.length
		MemFree txt
		Return True
	End Method
	
	Method NPObject(obj:TNPAPIObject)
		Int Ptr(_result + 0)[0] = 6
		Byte Ptr Ptr(_result + 1)[0] = (Byte Ptr(obj) - 8)
	End Method
	
	Method Hwnd()
		Return _hwnd
	End Method
	
	Method RegisterMethods()
		Local typ:TTypeId = TTypeId.ForObject(Self), name$ = typ.Name()
		If _methodmap.ValueForKey(name) = Null
			Local methods:TMap = New TMap
			For Local meth:TMethod = EachIn typ.EnumMethods()
				methods.Insert meth.Name(), meth
			Next
			_methodmap.Insert name, methods
		EndIf
	End Method
		
	Method FindMethod:TMethod(name$)
		Return TMethod(TMap(_methodmap.ValueForKey(TTypeId.ForObject(Self).Name())).ValueForKey(name))
	End Method
		
	Function GetData(obj:TNPAPIObject, so:Byte Ptr Ptr) "C"
		If Not obj.Scriptable() Return False
		so[0] = obj._scriptobject
		Return True
	End Function	
	
	Function SetData(obj:TNPAPIObject, so:Byte Ptr) "C"
		obj._scriptobject = so
	End Function	
	
	Function OnHasMethod(obj:TNPAPIObject, methodName:Byte Ptr) "C"
		Return obj.FindMethod(String.FromCString(methodName)) <> Null
	End Function
	
	Function OnInvoke(obj:TNPAPIObject, methodName:Byte Ptr, vargs:Byte Ptr, count, result:Byte Ptr) "C"		
		Local name$
		If methodName = Null
			name = "InvokeDefault"
		Else
			 name = String.FromCString(methodName)
		EndIf
		Local meth:TMethod = obj.FindMethod(name), args:Object[meth.ArgTypes().length]
		For Local i = 0 Until Min(args.length, count)
			Local arg:Byte Ptr = vargs + (16 * i)
			Select Int Ptr(arg + 0)[0]
			Case 2, 3
				args[i] = String(Int Ptr(arg + 8)[0])	
			Case 4
				args[i] = String(Double Ptr(arg + 8)[0])
			Case 5
				args[i] = String.FromCString(_npapi_get_string(arg))	
			End Select
		Next
		obj._result = result
		obj.NPVoid()
?Threaded
		LockMutex obj._mutex
?
		Local ret = Int(String(meth.Invoke(obj, args))) <> -1
?Threaded
		UnlockMutex obj._mutex
?
		Return ret
	End Function
	
	Function OnHandleEvent(obj:TNPAPIObject, event, wParam, lParam)
?Win32
		bbSystemEmitOSEvent( obj.Hwnd(), event,wParam,lParam,obj )
?
	End Function
	
	Function EventHook:Object(id, data:Object, context:Object)
		Local event:TEvent = TEvent(data)
		Local obj:TNPAPIObject = TNPAPIObject(event.source)
		If obj obj.OnEvent(event)
		Return data
	End Function
		
	Function OnSetWindow(obj:TNPAPIObject, hwnd)
?Win32
		If obj._hwnd <> hwnd And hwnd <> 0
			If obj._hwnd <> 0 SetWindowLongA(obj._hwnd,GWL_WNDPROC, Int(obj._wndproc))
			
			obj._wndproc = Byte Ptr(GetWindowLongA(hwnd,GWL_WNDPROC))
			SetWindowLongA(hwnd,GWL_WNDPROC, Int(Byte Ptr(WndProc)))
		
			_hwndmap.Insert String(hwnd), obj			
		EndIf
		obj._hwnd = hwnd
?
	End Function
	
	Function OnNewStream:Byte Ptr(obj:TNPAPIObject, p:Byte Ptr)
		Local stream:TNPAPIStream = New TNPAPIStream
		stream._ptr = p
		stream._link = obj._streams.AddLast(stream)
		Return Byte Ptr(stream) - 8
	End Function
	
	Function OnDestroyStream(obj:TNPAPIObject, stream:TNPAPIStream)
		Notify "DestroyStream"
		stream._link.Remove()
	End Function
	
	Function OnURLNotify(obj:TNPAPIObject, url:Byte Ptr, reason, data:Object)
		EmitEvent CreateEvent(EVENT_URLNOTIFY, obj, reason,,,,String.FromCString(url))
	End Function
	
	Function OnStreamAsFile(obj:TNPAPIObject, stream:TNPAPIStream, fname:Byte Ptr)
		Notify "StreamAsFile"
		EmitEvent CreateEvent(EVENT_STREAMASFILE, obj,,,,,String.FromCString(fname))
	End Function
	
	Function OnWrite(obj:TNPAPIObject, stream:TNPAPIStream, offset, length, buf:Byte Ptr)		
			Notify "OnWrite"
	End Function
	
	Function OnWriteReady(obj:TNPAPIObject, stream:TNPAPIStream)
			Notify "OnWriteREady"
	End Function
?Win32		
	Function WndProc(hwnd, msg, wParam, lParam)
		Local obj:TNPAPIObject = TNPAPIObject(_hwndmap.ValueForKey(String(hwnd)))
		OnHandleEvent(obj, msg, wParam, lParam)
		Return CallWindowProcA(obj._wndproc, hwnd, msg, wParam, lParam)
	End Function
?
End Type

Type TNPAPIPlugin
	Global _plugin:TNPAPIPlugin
	Field _objects:TTypeId[]
	Field _mimes$[],_descriptions$[]
	
	Field _instances:TNPAPIObject[]
	
	Method RegisterMime( mime$, obj:TNPAPIObject, description$ = "", exts$[] = Null)
		obj.RegisterMethods
		_mimes :+ [mime]
		_objects :+ [TTypeId.ForObject(obj)]
		_descriptions :+ [description]
	End Method
		
	Method New()
		_plugin = Self
	End Method
	
	Method Run()
		_plugin.Initialize
		
		?Debug
		Local base$ = StripAll(AppFile).Replace(".debug", "").Replace(".mt", "")
		Local def$ = "LIBRARY ~q"+base+".dll~q~nEXPORTS~n~nNP_GetEntryPoints~nNP_Initialize~nNP_Shutdown~nNP_Shutdown@0~n"
		SaveText def, AppDir+"/"+base+".def"
			
		Local header$=""
		header:+ "#define PLUGIN_COMPANYNAME ~q"+Author()+"~q~n"
		header:+ "#define PLUGIN_DESCRIPTION ~q"+Description()+"~q~n"
		header:+ "#define PLUGIN_DESC ~q"+"|".Join(_descriptions)+"~q~n"
		header:+ "#define PLUGIN_INTERNALNAME ~q"+Name().Replace(" ","")+"~q~n"
		header:+ "#define PLUGIN_COPYRIGHT ~q"+Copyright()+"~q~n"
		header:+ "#define PLUGIN_MIME ~q"+"|".Join(_mimes)+"~q~n"
		header:+ "#define PLUGIN_FILENAME ~q"+base+".dll~q~n"
		header:+ "#define PLUGIN_NAME ~q"+Name()+"~q~n"
		
		Local rc$ = LoadText("incbin::npapi.rc")
		SaveText header+rc, AppDir+"/"+base+".rc"
		system_ "windres ~q"+AppDir+"/"+base+".rc"+"~q ~q"+AppDir+"/resource.o~q"


		Local BMX_PATH$=getenv_("BMX_PATH")
		Local src$=ExtractDir(AppFile)+"/"+base+".bmx", opts$ = ""
		system_ BMX_PATH+"/bin/bmk makelib -a -r ~q"+src+"~q"
		?
	End Method
	
	Method MIMEDescription$()
		Local desc$
		For Local i = 0 To _objects.length-1
			desc:+ _mimes[i]+"::"+_descriptions[i]
			If i < _objects.length-1 desc:+";"
		Next
	End Method
	
	Method Initialize() Abstract
	Method Name$() Abstract
	Method Description$() Abstract
	Method Author$() Abstract
	Method Copyright$() Abstract
		
	Method Shutdown() ; End Method
	
	Function OnNew:Byte Ptr(instance:Byte Ptr, mime:Byte Ptr, argc, argn:Byte Ptr Ptr, argv:Byte Ptr Ptr) "C"
		Local map:TMap = CreateMap()
		For Local i = 0 Until argc
			MapInsert map, String.FromCString(argn[i]), String.FromCString(argv[i])
		Next

		Local m$=String.FromCString(mime)
		For Local i=0 To _plugin._objects.length-1
			If m = _plugin._mimes[i] 
				Local obj:TNPAPIObject = TNPAPIObject(_plugin._objects[i].NewObject())
				If obj.Initialize(map) <> 0 Return Null
				obj._instance = instance
				_plugin._instances :+ [obj]
				Return Byte Ptr(obj) - 8
			EndIf
		Next
	End Function
	
	Function OnDestroy(obj:TNPAPIObject)
		For Local i = 0 To _plugin._instances.length-1
			If _plugin._instances[i] = obj
				_plugin._instances = _plugin._instances[..i] + _plugin._instances[i+1..]
				obj.Destroy()
				Return
			EndIf
		Next
	End Function
	
	Function OnShutdown() "C"
		_plugin.Shutdown
	End Function

	Function GetMIMEDescription:Byte Ptr() "C"
		Global str:Byte Ptr = Null
		If str = Null str = _plugin.MIMEDescription().ToCString()
		Return str
	End Function
	
	Function GetName:Byte Ptr() "C"
		Global str:Byte Ptr = Null
		If str = Null str = _plugin.Name().ToCString()
		Return str
	End Function
	
	Function GetDescription:Byte Ptr() "C"
		Global str:Byte Ptr = Null
		If str = Null str = _plugin.Description().ToCString()
		Return str
	End Function
	
	Function Message(msg:Byte Ptr)
		Notify String.FromCString(msg)
	End Function
End Type

AddHook EmitEventHook, TNPAPIObject.EventHook
