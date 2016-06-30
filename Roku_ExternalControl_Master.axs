PROGRAM_NAME='Roku_ExternalControl_Master'

DEFINE_DEVICE
    dvIP_Roku = 0:3:0
    dvTP_Roku = 10001:1:0
    vdvRoku = 33001:1:0
    
DEFINE_MODULE 'Roku_Comm' comm1(vdvRoku,dvIP_Roku)
DEFINE_MODULE 'Roku_UI' ui1(vdvRoku,dvTP_Roku)

DEFINE_EVENT
    DATA_EVENT [vdvRoku] {
	ONLINE : {
	    SEND_COMMAND vdvRoku,"'PROPERTY-IP_Address,192.168.3.100'"
	}
    }