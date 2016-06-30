MODULE_NAME='Roku_Comm' (DEV vdvDev,DEV dvDev)
#INCLUDE 'SNAPI'

DEFINE_TYPE
    STRUCTURE _Debug {
	INTEGER nDebugLevel		//---Current level of debug strings sent to console (See DebugString subroutine below)
    }
    STRUCTURE _Comm {
	CHAR cIPAddress[15]		//---IP Address of the Boxee Box (? Increase byte count to allow for hostnames ?)
	INTEGER nTCPPort		//---Default from Boxee is 8800 for API calls
	INTEGER nCommTimeout		//---How long before we give up on a response?
	
	CHAR cQue[2048]			//---Que of strings waiting to be sent to device
	CHAR cBuf[4096]			//---Buffer of Acks returned from device
	CHAR cLastGet[512]		//---What was the last request I sent to the device?
	INTEGER nBusy			//---Waiting for a response back from the device
	
	LONG lPollTime			//---How frequently should we poll (Thousandths)
    }
    STRUCTURE _Roku {
	_Comm Comm			//---See notes above
	_Debug Debug			//---See notes above
	
	INTEGER nProgressPoll
	INTEGER nPlaying
    }

DEFINE_VARIABLE
    VOLATILE _Roku Roku
    
DEFINE_VARIABLE	
    CONSTANT tlPolling = 1
    CONSTANT MaxPollCmds = 1
    VOLATILE LONG lTimes[] = { 500,60000 }
    VOLATILE CHAR cPollCmds[2][32] = { '' }

//-----------------------------------------------------------------------------

DEFINE_FUNCTION DebugString(INTEGER nLevel,CHAR cString[]) {
    //---Sends the appropriate debug strings to the console.
    //---1-ERRORS Only
    //---2-Asynchronous Strings from Device
    //---3-Acks to code driven actions
    //---4-All Data & parsing)
    
    IF(nLevel<=Roku.Debug.nDebugLevel) {
	SEND_STRING 0,"'BoxeeBox - ',cString"
    }
}


DEFINE_FUNCTION SendQue() {
    //---Waits until we are not waiting for a response from device.
    //---Checks to see if there is anything to send.
    //---Resides in mainline.
    
    LOCAL_VAR CHAR cCmd[64]
    IF(!Roku.Comm.nBusy && FIND_STRING(Roku.Comm.cQue,"$0B,$0B",1)) {
	ON[Roku.Comm.nBusy]
	CALL 'OpenSocket'
    }
}


DEFINE_FUNCTION AddHTTPGet(CHAR cShortURI[]) {
    //---Add an HTTP GET request to Roku.Comm.cQue
    //---To be instantiated by SendQue above
    
    STACK_VAR CHAR cURLString[512]
    STACK_VAR CHAR cHeader[512]
    
    cURLString = "'/',cShortURI"
    DebugString(4,"'Add to Que: HTTP://',Roku.Comm.cIPAddress,cURLString")
    
    cHeader = "'GET ',cURLString,' HTTP/1.1',$0D,$0A"
    cHeader = "cHeader,'Host: ',Roku.Comm.cIPAddress,$0D,$0A"
    cHeader = "cHeader,'User-Agent: Mozilla/5.0 (Windows NT 6.1; WOW64,rv:13.0) Gecko/20100101 Firefox/13.0.1',$0D,$0A"
    cHeader = "cHeader,'Accept: text/html,application/xhtml+xml,application/xml;q=0.9*/*;q=0.8',$0D,$0A"
    cHeader = "cHeader,'Accept-Language: en-us;q=0.5',$0D,$0A"
    cHeader = "cHeader,'Accept-Encoding: gzip,deflate',$0D,$0A"
    cHeader = "cHeader,'Connection: keep-alive',$0D,$0A,$0D,$0A"
    
    Roku.Comm.cQue = "Roku.Comm.cQue,cHeader,$0B,$0B"
    DebugString(3,"'AddHTTPGet : ',cShortURI")
}


DEFINE_CALL 'OpenSocket' {
    //---Opens a client socket and waits for the device to come online
    //---Errors listed are those reported by AMX socket handler

    STACK_VAR SINTEGER nError 
    STACK_VAR CHAR cError[32]
    
    nError = IP_CLIENT_OPEN(dvDev.PORT,Roku.Comm.cIPAddress,Roku.Comm.nTCPPort,IP_TCP)
    
    SWITCH(nError) {
	CASE 0	: cError='None'
	CASE 2  : cERROR='General Failure'
	CASE 4  : cERROR='Unknown Host'
	CASE 6  : cERROR='Connection Refused'
	CASE 7  : cERROR='Connection Timed Out'
	CASE 8  : cERROR='Unknown Connection Error'
	CASE 14 : cERROR='Local Port Already in Use'
	CASE 16 : cERROR='Too Many Open Sockets'
	CASE 17 : cERROR='Local Port Not Open'
	DEFAULT : cERROR=ITOA(nERROR)
    }
    IF(nError) {
	SEND_STRING vdvDev,"'ERROR-Socket Connection Error: ',cError"
	DebugString(1,"'ERROR-Socket Connection Error: ',cError")
    }
    ELSE {
	DebugString(3,"'OpenSocket - Socket opened successfully'")
    }
}

//-----------------------------------------------------------------------------Parsing Routines

DEFINE_FUNCTION DevRx(CHAR cBuf[]) {
    //---Received a string from the device,
    //---Now lets do something intelligent with it.

    STACK_VAR CHAR cHTTPResponseCode[8]
    STACK_VAR LONG nHTMLStart
    STACK_VAR LONG nHTMLEnd
    STACK_VAR CHAR cHTML[2048]
    STACK_VAR CHAR cAck[2048]
    STACK_VAR CHAR cTempPara[2][128]
    STACK_VAR INTEGER nTempPara
    STACK_VAR INTEGER nPointer
    
    //DebugString(4,"'Parsing : ',cBuf")
    
    REMOVE_STRING(cBuf,"$0D,$0A,$0D,$0A,'b',$0D,$0A",1)
    SET_LENGTH_STRING(cBuf,LENGTH_STRING(cBuf)-7)
    
    //DebugString(4,"'Parse-able data : ',cBuf")
    //---Responses are too long for a single line in debug
    //---Break it up into usable chunks.
    nPointer = 1
    WHILE(LENGTH_STRING(cBuf)>nPointer) {
	DebugString(4,"'Parsing : ',MID_STRING(cBuf,nPointer,120)")
	nPointer = nPointer+120
    }
    
    REMOVE_STRING(cBuf,"'HTTP/1.0 '",1)
    cHTTPResponseCode = REMOVE_STRING(cBuf,"$0D,$0A",1)
    
    SELECT {
	//---HTTP Error Codes from Device
	ACTIVE (FIND_STRING(cHTTPResponseCode,'401',1)) : DebugString(1,'ERROR - HTTP Response Code: 401, Unauthorized')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'402',1)) : DebugString(1,'ERROR - HTTP Response Code: 402, Payment Required')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'403',1)) : DebugString(1,'ERROR - HTTP Response Code: 403, Forbidden')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'404',1)) : DebugString(1,'ERROR - HTTP Response Code: 404, Not Found')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'405',1)) : DebugString(1,'ERROR - HTTP Response Code: 405, Method Not Allowed')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'406',1)) : DebugString(1,'ERROR - HTTP Response Code: 406, Not Acceptible')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'407',1)) : DebugString(1,'ERROR - HTTP Response Code: 407, Proxy Auth Required')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'408',1)) : DebugString(1,'ERROR - HTTP Response Code: 408, Request Timeout')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'409',1)) : DebugString(1,'ERROR - HTTP Response Code: 409, Conflict')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'410',1)) : DebugString(1,'ERROR - HTTP Response Code: 410, Gone')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'411',1)) : DebugString(1,'ERROR - HTTP Response Code: 411, Length Required')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'412',1)) : DebugString(1,'ERROR - HTTP Response Code: 412, Precondition Failed')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'413',1)) : DebugString(1,'ERROR - HTTP Response Code: 413, Request Entity Too Large')
	ACTIVE (FIND_STRING(cHTTPResponseCode,'414',1)) : DebugString(1,'ERROR - HTTP Response Code: 414, Request URI Too Long')
	
	//---Acknowledgement of Properly encoded message
	ACTIVE (FIND_STRING(cHTTPResponseCode,'200 OK',1)) : {
	    DebugString(4,'HTTP Response Code: 200, OK!')
	    
	    nHTMLStart = FIND_STRING(cBuf,'<html>',1)
	    nHTMLEnd = FIND_STRING(cBuf,'</html>',1)
	    cHTML = MID_STRING(cBuf,nHTMLStart,(nHTMLEnd-nHTMLStart))
	    DebugString(4,"'HTML Content - ',cHTML")
	    
	}
    }
}

//-----------------------------------------------------------------------------

DEFINE_EVENT
    DATA_EVENT [vdvDev] {
	ONLINE : {
	    //---Default poll time
	    //SEND_COMMAND vdvDev,"'PROPERTY-Poll_Time,60'"
	}
	COMMAND : {
	    //---Parse commands send to the virtual from Master code.
	    //---Que up the appropriate requests to the device
	    
	    STACK_VAR CHAR cCmd[16]
	    STACK_VAR INTEGER nPara
	    STACK_VAR CHAR cPara[8][128]
	    
	    cCmd = DuetParseCmdHeader(DATA.TEXT)
	    
	    nPara = 1
	    WHILE(FIND_STRING(DATA.TEXT,',',1)) {
		cPara[nPara] = DuetParseCmdParam(DATA.TEXT)
		nPara++
	    }
	    cPara[nPara] = DuetParseCmdParam(DATA.TEXT)
	    
	    SELECT {
		
		(*********************************************************************)
		
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='HOME')) : AddHTTPGet('Keypress/Home')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='REV')) : AddHTTPGet('Keypress/Rev')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='FWD')) : AddHTTPGet('Keypress/Fwd')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='PLAY')) : AddHTTPGet('Keypress/Play')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='SELECT')) : AddHTTPGet('Keypress/Select')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='LEFT')) : AddHTTPGet('Keypress/Left')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='RIGHT')) : AddHTTPGet('Keypress/Right')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='DOWN')) : AddHTTPGet('Keypress/Down')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='UP')) : AddHTTPGet('Keypress/Up')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='BACK')) : AddHTTPGet('Keypress/Back')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='REPLAY')) : AddHTTPGet('Keypress/InstantReplay')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='INFO')) : AddHTTPGet('Keypress/Info')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='BACKSPACE')) : AddHTTPGet('Keypress/Backspace')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='SEARCH')) : AddHTTPGet('Keypress/Search')
		ACTIVE ((cCmd=='KEYPRESS') && (UPPER_STRING(cPara[1])=='ENTER')) : AddHTTPGet('Keypress/Enter')
		
		ACTIVE (cCmd=='KEYBOARD') : AddHTTPGet("'Keypress/Lit_',cPara[1]")
		
		
		(*********************************************************************)
		
		//---Commands below are module-specific, and don't necessarily have direct
		//---requests to the device associated.  These are how the module is instantiated
		//---and/or modified at runtime.
		
		ACTIVE (cCmd=='PASSTHRU_GET') : {
		    AddHTTPGet(cPara[1])
		}
		
		ACTIVE (cCmd=='DEBUG') : {
		    Roku.Debug.nDebugLevel = ATOI(cPara[1])
		    SEND_STRING vdvDev,"'DEBUG-',cPara[1]"
		    DebugString(0,"'DEBUG Level = ',cPara[1]")
		}
		ACTIVE ((cCmd=='PROPERTY') && (cPara[1]=='IP_Address')) : {
		    Roku.Comm.cIPAddress = cPara[2]
		    SEND_STRING vdvDev,"'PROPERTY-IP_Address,',cPara[2]"
		    DebugString(3,"'IP Address: ',cPara[2]")
		}
		ACTIVE ((cCmd=='PROPERTY') && (cPara[1]=='TCP_Port')) : {
		    Roku.Comm.nTCPPort = ATOI(cPara[2])
		    SEND_STRING vdvDev,"'PROPERTY-TCP_Port,',cPara[2]"
		    DebugString(3,"'TCP Port : ',cPara[2]")
		}
		ACTIVE ((cCmd=='PROPERTY') && (cPara[1]=='Poll_Time')) : {
		    Roku.Comm.lPollTime = ATOI(cPara[2])*1000
		    lTimes[MaxPollCmds+1] = Roku.Comm.lPollTime
		    SEND_STRING vdvDev,"'PROPERTY-Poll_Time,',ITOA(Roku.Comm.lPollTime)"
		    
		    IF(TIMELINE_ACTIVE(tlPolling))
			TIMELINE_KILL(tlPolling)
		    
		    IF(Roku.Comm.lPollTime > 0)
			TIMELINE_CREATE(tlPolling,lTimes,MaxPollCmds+1,TIMELINE_RELATIVE,TIMELINE_REPEAT)
		}
		ACTIVE ((cCmd=='PROPERTY') && (cPara[1]=='Progress_Poll')) : {
		    Roku.nProgressPoll = ATOI(cPara[2])
		    SEND_STRING vdvDev,"'PROPERTY-Progress_Poll,',ITOA(Roku.nProgressPoll)"
		}
		
		ACTIVE (cCmd=='CLEARQUE') : {
		    Roku.Comm.cQue = ''
		}
		ACTIVE (cCmd=='CLEARBUF') : {
		    Roku.Comm.cBuf = ''
		    OFF[Roku.Comm.nBusy]
		}
		ACTIVE (cCmd=='REINIT') : {
		    Roku.Comm.cQue = ''
		    Roku.Comm.cBuf = ''
		    ON[Roku.Comm.nBusy]
		    IP_CLIENT_CLOSE(dvDev.PORT)
		    WAIT 10
			OFF[Roku.Comm.nBusy]
		}
		
		//---When all else fails, throw up an error flag!
		ACTIVE (1) : DebugString(1,"'ERROR - Unhandled Command'")
	    }
	}
    }
    DATA_EVENT [dvDev] {
	ONLINE : {
	    STACK_VAR CHAR cPayload[512]
	    STACK_VAR INTEGER nLastCmdStart
	    STACK_VAR INTEGER nLastCmdEnd
	    
	    cPayload = REMOVE_STRING(Roku.Comm.cQue,"$0B,$0B",1)
	    SEND_STRING dvDev,"cPayload"
	    
	    WAIT Roku.Comm.nCommTimeout 'CommTimeout' {
		Roku.Comm.cBuf = ''
		Roku.Comm.cQue = ''
		IP_CLIENT_CLOSE(dvDev.Port)
		OFF[Roku.Comm.nBusy]
		SEND_STRING vdvDev,"'ERROR-Comm Timeout'"
		DebugString(1,"'ERROR-Comm Timed Out'")
	    }
	}
	OFFLINE : {
	    LOCAL_VAR INTEGER nPointer
	    OFF[Roku.Comm.nBusy]
	    IF(LENGTH_STRING(Roku.Comm.cBuf)) {
		
		//DebugString(3,"'Sending to Parse : ',Roku.Comm.cBuf")
		nPointer = 1
		WHILE(LENGTH_STRING(DATA.TEXT)>nPointer) {
		    DebugString(4,"'Send to Parse : ',MID_STRING(DATA.TEXT,nPointer,120)")
		    nPointer = nPointer+120
		}
		
		DevRx(Roku.Comm.cBuf)
		Roku.Comm.cBuf = ''
	    }
	}
	STRING : {
	    CANCEL_WAIT 'CommTimeout'
	    //DebugString(4,"'Rx from BoxeeBox: ',DATA.TEXT")
	    IF(RIGHT_STRING(Roku.Comm.cBuf,7)=="$0D,$0A,'0',$0D,$0A,$0D,$0A")
		IP_CLIENT_CLOSE(dvDev.PORT)
	}
    }


DEFINE_EVENT
    CHANNEL_EVENT [vdvDev,PLAY] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-Play'"
    }
    CHANNEL_EVENT [vdvDev,STOP] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-Stop'"
    }
    CHANNEL_EVENT [vdvDev,PAUSE] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-Play'"
    }
    CHANNEL_EVENT [vdvDev,SFWD] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-Fwd'"
    }
    CHANNEL_EVENT [vdvDev,SREV] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-Rev'"
    }
    
    CHANNEL_EVENT [vdvDev,DIGIT_0]
    CHANNEL_EVENT [vdvDev,DIGIT_1]
    CHANNEL_EVENT [vdvDev,DIGIT_2]
    CHANNEL_EVENT [vdvDev,DIGIT_3]
    CHANNEL_EVENT [vdvDev,DIGIT_4]
    CHANNEL_EVENT [vdvDev,DIGIT_5]
    CHANNEL_EVENT [vdvDev,DIGIT_6]
    CHANNEL_EVENT [vdvDev,DIGIT_7]
    CHANNEL_EVENT [vdvDev,DIGIT_8]
    CHANNEL_EVENT [vdvDev,DIGIT_9] {
	ON : SEND_COMMAND vdvDev,"'KEYBOARD-',ITOA(CHANNEL.CHANNEL-10)"
    }
    
    // menu
    CHANNEL_EVENT [vdvDev,MENU_CLEAR]
    CHANNEL_EVENT [vdvDev,MENU_FUNC] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-HOME'"
    }
    CHANNEL_EVENT [vdvDev,MENU_UP] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-UP'"
    }
    CHANNEL_EVENT [vdvDev,MENU_DN] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-DOWN'"
    }
    CHANNEL_EVENT [vdvDev,MENU_LT] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-LEFT'"
    }
    CHANNEL_EVENT [vdvDev,MENU_RT] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-RIGHT'"
    }
    CHANNEL_EVENT [vdvDev,MENU_SELECT] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-SELECT'"
    }
    CHANNEL_EVENT [vdvDev,MENU_BACK]
    CHANNEL_EVENT [vdvDev,MENU_EXIT] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-BACK'"
    }
    
    
    CHANNEL_EVENT [vdvDev,MENU_INSTANT_REPLAY] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-REPLAY'"
    }
    CHANNEL_EVENT [vdvDev,MENU_BACK] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-BACK'"
    }
    CHANNEL_EVENT [vdvDev,MENU_INFO] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-INFO'"
    }
    CHANNEL_EVENT [vdvDev,1000] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-SEARCH'"
    }
    CHANNEL_EVENT [vdvDev,1001] {
	ON : SEND_COMMAND vdvDev,"'KEYPRESS-BACKSPACE'"
    }
    
    
DEFINE_EVENT
    TIMELINE_EVENT [tlPolling] {
	IF(TIMELINE.SEQUENCE<=MaxPollCmds)
	    SEND_COMMAND vdvDev,"cPollCmds[TIMELINE.SEQUENCE]"
    }
    
//-----------------------------------------------------------------------------

DEFINE_START
    CREATE_BUFFER dvDev,Roku.Comm.cBuf
    Roku.Comm.nTCPPort = 8060
    Roku.Comm.nCommTimeout = 50
    Roku.nProgressPoll = 0


//-----------------------------------------------------------------------------

DEFINE_PROGRAM
    WAIT 1 {
	[vdvDev,1] = Roku.nPlaying
	
	[vdvDev,254] = Roku.Comm.nBusy
	SendQue()
    }
	
    (*
    WAIT 10
	IF(Roku.nProgressPoll)
	    SEND_COMMAND vdvDev,"'?NOW_PLAYING'"
    *)