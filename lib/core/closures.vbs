Option Explicit
'
' closures.vbs
' Copyright (C) Brian Lauber 2010 <constructible.truth@gmail.com>
'
' Tolerable is free software: you can redistribute it and/or modify it
' under the terms of the GNU Lesser General Public License as published
' by the Free Software Foundation, either version 3 of the License, or
' (at your option) any later version.
'
' Tolerable is distributed in the hope that it will be useful, but
' WITHOUT ANY WARRANTY; without even the implied warranty of
' MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
' See the GNU Lesser General Public License for more details.
'
' You should have received a copy of the GNU Lesser General Public License
' along with this program.  If not, see <http://www.gnu.org/licenses/>.
'



Require "t\core\assignment.vbs"
Require "t\core\linked_list.vbs"


Require "t\core\memoizer.vbs"

' When a Closure goes out of scope, it will destroy
' its Closure_NameHandle instance.  This will cause
' the closure's name to be returned to a pool of
' available function names.
Class Closure_NameHandle_Class
	Private m_name
	Private m_owner_queue
	
	Public Sub Initialize(ByVal name, ByVal owner_queue)
		m_name = name
		Set m_owner_queue = owner_queue
	End Sub
	
	Private Sub Class_Terminate()
		m_owner_queue.Push m_name
	End Sub
	
	Public Property Get Name
		Name = m_name
	End Property
End Class


' Closures do not simply call Eval(...) on strings.
' They actually pre-compile the code into an actual
' function.  To eliminate the possibility of compiling
' millions of functions during the lifetime of an
' application, we reuse function names.  The
' Closure_NameManager and Closure_NameHandle classes
' work together to keep track of which names are
' available for reuse.
Class Closure_NameManager_Class
	Private m_available
	Private m_next
	
	Private Sub Class_Initialize()
		Set m_available = LinkedList()
		m_next          = 0
	End Sub
	
	Private Sub Class_Terminate()
		Set m_available = Nothing
	End Sub
	
	Public Function GetName()
		Dim retval
		Set retval = New Closure_NameHandle_Class
		
		If m_available.IsEmpty Then
			retval.Initialize "ClosureInstance___" & m_next, m_available
			m_next = m_next + 1
		Else
			retval.Initialize m_available.Pop, m_available
		End If
		
		Set GetName = retval
	End Function
End Class







' Bootstrapping: Define the constructor for 0-arg closures upfront
Private Function ClosureFactory_CreateClosure0()
    Set ClosureFactory_CreateClosure0 = New ClosureFactory_ClosureClass0
End Function


' This class generates Closure classes on demand.
Class ClosureFactory_Class
	Private m_name_generator
    Private m_constructors
    
    Private m_func_signature
    Private m_invoke_args
    Private m_byval_args
    Private m_byref_args
    
    Private Sub Class_Initialize()
		Set m_name_generator  = New Closure_NameManager_Class
        Set m_constructors    = CreateObject("Scripting.Dictionary")

        ' It would be nice if I could just set these up using Memoizers
        Set m_func_signature = CreateObject("Scripting.Dictionary")
        Set m_invoke_args    = CreateObject("Scripting.Dictionary")
        Set m_byval_args     = CreateObject("Scripting.Dictionary")
        Set m_byref_args     = CreateObject("Scripting.Dictionary")

        ' Bootstrap this w/ the 0-arg closure constructor.  All future
        ' constructors can be written using Closures.  Boo-yah!
        GenerateClass 0
        m_constructors.Add 0, GetRef("ClosureFactory_CreateClosure0")
    End Sub
    
    Private Sub Class_Terminate()
		Set m_name_generator  = Nothing
        Set m_constructors    = Nothing
        
        Set m_func_signature  = Nothing
        Set m_invoke_args     = Nothing
        Set m_byval_args      = Nothing
        Set m_byref_args      = Nothing
    End Sub    
    
    
    
    Public Function ArgName(ByVal index)
        ArgName = "arg" & index
    End Function
    
    
    Private Function FuncSignature(ByVal arg_count)
        If Not m_func_signature.Exists(arg_count) Then
            Dim   max           : max = arg_count - 1
            ReDim arg_list(max)
            Dim   i
            For i = 0 To max
                arg_list(i) = ", " & ArgName(i)
            Next
            
            m_func_signature.Add arg_count, "(ByRef Invoke, ByRef stored" & Join(arg_list, "") & ")"
        End If
        FuncSignature = m_func_signature.Item(arg_count)
    End Function

    ' Creates a comma-separated list of argument names.
    ' Useful when you are generating code that will invoke
    ' a function.
    Public Function InvokeArgs(ByVal arg_count)
        If Not m_invoke_args.Exists(arg_count) Then
            
            Dim   max           : max = arg_count - 1
            ReDim arg_list(max)
            Dim   i
            For i = 0 To max
                arg_list(i) = ArgName(i)
            Next
            m_invoke_args.Add arg_count, Join(arg_list, ", ")
        End If
        InvokeArgs = m_invoke_args.Item(arg_count)
    End Function
    
    
    ' Creates a comma-separated list of ByVal args.
    ' Useful for generating function declarations.
    Public Function ByValArgs(ByVal arg_count)
        If Not m_byval_args.Exists(arg_count) Then
            
            Dim   max           : max = arg_count - 1
            ReDim arg_list(max)
            Dim   i
            For i = 0 To max
                arg_list(i) = "ByVal " & ArgName(i)
            Next
            m_byval_args.Add arg_count, Join(arg_list, ", ")
        End If
        ByValArgs = m_byval_args.Item(arg_count)
    End Function
    
    
    ' Creates a comma-separated list of ByRef args.
    ' Useful for generating function declarations.
    Public Function ByRefArgs(ByVal arg_count)
        If Not m_byref_args.Exists(arg_count) Then
            
            Dim   max           : max = arg_count - 1
            ReDim arg_list(max)
            Dim   i
            For i = 0 To max
                arg_list(i) = "ByRef " & ArgName(i)
            Next
            m_byref_args.Add arg_count, Join(arg_list, ", ")
        End If
        ByRefArgs = m_byref_args.Item(arg_count)
    End Function
    
    
    
    
    
    
    Private Function ClassName(ByVal arg_count)
        ClassName = "ClosureFactory_ClosureClass" & arg_count
    End Function


    Private Function ClassCode(ByVal arg_count)
        Dim invoke_args
        If arg_count = 0 Then
            invoke_args = ""
        Else
            invoke_args = ", " & InvokeArgs(arg_count)
        End If

        ClassCode = _
            "Class " & ClassName(arg_count) & vbCR &_
            "    Private m_reserved_name" & vbCR &_
            "    Private m_stored" & vbCR &_
            "    Private m_func" & vbCR &_
            "    Public Sub Initialize(ByVal reserved_name, ByVal storage, ByVal func)" & vbCR &_
            "        Set m_reserved_name = reserved_name" & vbCR &_
            "        Assign m_stored, storage" & vbCR &_
            "        Set m_func          = func" & vbCR &_
            "    End Sub" & vbCR &_
            "    Private Sub Class_Terminate()" & vbCR &_
            "        Set m_func          = Nothing" & vbCR &_
            "        Set m_stored        = Nothing" & vbCR &_
            "        Set m_reserved_name = Nothing" & vbCR &_
            "    End Sub" & vbCR &_
            "    Public Default Function Invoke(" & ByRefArgs(arg_count) & ")" & vbCR &_
            "        Dim retval" & vbCR &_
            "        m_func retval, m_stored" & invoke_args & vbCR &_
            "        If IsObject(retval) Then" & vbCR &_
            "            Set Invoke = retval" & vbCR &_
            "        Else" & vbCR &_
            "            Invoke = retval" & vbCR &_
            "        End If" & vbCR &_
            "    End Function" & vbCR &_
            "End Class"
    End Function

    
    Public Sub GenerateClass(ByVal arg_count)
        ExecuteGlobal ClassCode(arg_count)
    End Sub



    Public Function Create(ByVal arg_count, ByVal storage, ByVal statements)
        If Not m_constructors.Exists(arg_count) Then
            GenerateClass arg_count
            m_constructors.Add arg_count, Lambda(0, Nothing, "Set Invoke = New " & ClassName(arg_count))
        End If

        Dim r : Set r = m_name_generator.GetName

        ' Compile the function
        ExecuteGlobal _
            "Private Function " & r.Name & FuncSignature(arg_count) & vbCR &_
            statements & vbCR &_
            "End Function"
        
        ' Create the Closure object that will point to this function
        Dim c      : Set c = m_constructors(arg_count)
        Dim retval : Set retval = c()
        retval.Initialize r, storage, GetRef(r.Name)

        Set Create = retval
    End Function

End Class


Dim ClosureFactory_Singleton__
Public Function ClosureFactory()
    If IsEmpty(ClosureFactory_Singleton__) Then
        Set ClosureFactory_Singleton__ = New ClosureFactory_Class
    End If
    Set ClosureFactory = ClosureFactory_Singleton__
End Function


Public Function Lambda(ByVal arg_count, ByVal storage, ByVal statements)
    Set Lambda = ClosureFactory.Create(arg_count, storage, statements)
End Function



' If obj is a String, then convert it into a Lambda
' with arg_count arguments.  Otherwise, return obj
Public Function TO_Expr(ByVal arg_count, ByVal obj)
    If TypeName(obj) = "String" Then
        Set TO_Expr = Lambda(arg_count, Array(), "Assign Invoke, (" & obj & ")")
    Else
        Set TO_Expr = obj
    End If
End Function

' If obj is a String, then convert it into a Lambda
' with arg_count arguments.  Otherwise, return obj
Public Function TO_Sub(ByVal arg_count, ByVal obj)
    If TypeName(obj) = "String" Then
        Set TO_Sub = Lambda(arg_count, Array(), obj)
    Else
        Set TO_Sub = obj
    End If
End Function




' Allows single-quotes to be used in place of double-quotes.
' Basically, this is a cheap trick that can make it easier
' to specify Lambdas.
Public Function Q(ByVal input)
    Q = Replace(input, "'", """")
End Function


' Lambda function that will invert the output of any conditional
Public Function L_Not(ByVal arg_count, ByVal func)
    Set L_Not = Lambda(arg_count, _
                       Array(TO_Expr(arg_count, func)), _
                       "Assign Invoke, Not(stored(0)(" & ClosureFactory.GetArgList(arg_count).Args & "))")
End Function




