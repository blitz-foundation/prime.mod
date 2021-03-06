
Strict

Module Prime.AssetManager
ModuleInfo "Author: Kevin Primm"
ModuleInfo "License: MIT"

Import BRL.FileSystem
Import BRL.Map
Import BRL.TextStream
Import Prime.MaXML

Type TAssetManager
	Field _assets:TMap=CreateMap()
	Field _ids$[]
	
	Method Load(url:Object)
		Local doc:xmlDocument=New xmlDocument
		doc.Load url
		Local root:xmlNode=doc.Root()
		If root.Name<>"assets" Return False
		For Local node:xmlNode=EachIn root.ChildList
			ParseNode(node,"",root.Attribute("dir").Value+"/")
		Next
		Local new_ids$[]
		For Local key:Object=EachIn MapKeys(_assets)
			new_ids:+[String(key)]
		Next
		_ids:+new_ids
	End Method
	
	Method ParseNode(node:xmlNode,id$,dir$)
		Select node.Name
		Case "group"
			If node.HasAttribute("dir")
				dir:+node.Attribute("dir").Value
				If node.HasAttribute("id") id:+node.Attribute("id").Value+"_"
			Else
				If node.HasAttribute("id")
					dir:+node.Attribute("id").Value+"/"
					id:+node.Attribute("id").Value+"_"
				EndIf
			EndIf
			For Local child:xmlNode=EachIn node.ChildList
				ParseNode(child,id,dir)
			Next
		Case "set"
			For Local child:xmlNode=EachIn node.ChildList
				For Local attr:xmlAttribute=EachIn node.AttributeList
					If Not child.HasAttribute(attr.Name) child.Attribute(attr.Name).Value=attr.Value
				Next
				ParseNode child,id,dir
			Next
		Default
			Local params:TMap=GetParams(node)
			Local obj:Object=TAssetLoader.Load(dir+node.Attribute("url").Value,node.Name,params)
			If obj<>Null
				Local obj_id$
				If Not node.HasAttribute("id")
					obj_id=StripAll(node.Attribute("url").Value)
				Else
					obj_id=node.Attribute("id").Value
				EndIf
				_assets.Insert(id+obj_id,obj)
			Else
				DebugLog "Failed to load ~q"+dir+node.Attribute("url").Value+"~q"
			EndIf
		End Select
	End Method
	
	Method GetParams:TMap(node:xmlNode)
		Local params:TMap=CreateMap()		
		For Local attr:xmlAttribute=EachIn node.AttributeList
			params.Insert(attr.Name,attr.Value)
		Next
		Return params
	End Method
	
	Method List$[]()
		Local l$[]
		For Local key:Object=EachIn MapKeys(_assets)
			l=l[..l.length+1]
			l[l.length-1]=String(key)
		Next
		Return l
	End Method
	
	Method Get:Object(id$)
		Return _assets.ValueForKey(id)
	End Method
	
	Method Multiget:Object[](id$)
		Local objs:Object[]
		For Local key$=EachIn _ids
			If key[..id.length]=id objs:+[Get(key)]
		Next
		Return objs
	End Method
End Type

Type TAssetLoader
	Global _first:TAssetLoader
	Field _next:TAssetLoader,_params:TMap
	
	Method New()
		If _first=Null
			_first=Self
		Else
			Local loader:TAssetLoader=_first
			While loader._next
				loader=loader._next
			Wend
			loader._next=Self
		EndIf
	End Method
	
	Function Load:Object(url:Object,typ$="",params:TMap=Null)
		Local loader:TAssetLoader=_first
		While loader
			If (loader.GetType()=typ And typ<>"") Or typ=""
				loader._params=params
				Local obj:Object=loader.Run(url)
				loader._params=Null
				If obj Return obj
			EndIf
			loader=loader._next
		Wend
	End Function
	
	Method GetStream:TStream(url:Object)
		Local stream:TStream=TStream(url)
		If stream=Null stream=ReadStream(url)
		If stream=Null Return Null
	End Method
	
	Method Param:Object(key$,def:Object=Null)
		If Not ParamExists(key) Return def
		Return _params.ValueForKey(key)
	End Method
	
	Method IParam(key$,def=0)
		Return Int(SParam(key,def))
	End Method
	
	Method SParam$(key$,def$="")
		Return String(Param(key,String(def)))
	End Method
	
	Method SAParam$[](key$,delim$,def$="")
		Return SParam(key,def).Split(delim)
	End Method
	
	Method ParamExists(key$)
		Return _params.ValueForKey(key)<>Null
	End Method
	
	Method Run:Object(url:Object) Abstract
	Method GetType$() Abstract
End Type
