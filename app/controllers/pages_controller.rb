require "zlib"
require "geoscan_util"

class PagesController < ApplicationController
  def home
    if user_signed_in?
      if current_user.admin?
        redirect_to projects_path
      else
        if current_user.project
          redirect_to report_project_path(current_user.project)
        end
      end
    else
      redirect_to new_user_session_path
    end
  end
  @@flagtime||=DateTime.now
  def input
    if !params[:device_id].nil? and !params[:crc32].nil? and !params[:summary].nil? and !params[:data].nil?
      if verify_data params[:summary], params[:data], params[:crc32]
        data = params[:device_id].unpack("VV") #retrive device id here
        device_id = "#{data[0].to_s(16)}#{data[1].to_s(16)}"#convert data to string?
        @device_id=device_id
        
        data = params[:summary].unpack("VVVVvvffffffff")
        msgtype = data[0]   #retrive msg type here
	#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	handphone=data[3].to_s #=>handphone="83576637"
	batteryvoltage=data[4].to_f #batteryvoltage=12.75
	csq=data[5].to_i #csq=101
	#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~							
#*********************************************************************************#
#**update regardless of is in project? because it's the property of concentrator**#
	@constatus=Concentrator.find_by_device_id(device_id) #12103695524181812 if no working device id wrong
	@constatus.update_attributes(battery_voltage: batteryvoltage/100,concentrator_hp: handphone,concentrator_csq:csq) rescue nil	
#********************************************************************************# 

        if msgtype == 0x00              #config and set concentrator
          concentrators_set = Concentrator.where(device_id: device_id) #lock a row
          
          if concentrators_set.count > 0 #more than 0 row=record exists
            concentrator = concentrators_set.first #just 1 row,so select 1st
           if !concentrator.project.blank? and concentrator.project.status == "Ongoing"
              concentrator.update_attributes last_assigned_ip_address: request.remote_ip, last_communication_packet_sent: Time.now.utc 
              render json: { status: true }
            else
              render json: { error: "Project is not currently running" }
            end
          else
            render json: { error: "Concentrator is not available" }
          end
        else
          timestamp = data[1]
          time = DateTime.strptime(timestamp.to_s,'%s') #input time 
          timeforcheck=DateTime.now #fu's variable
          serial = data[2].to_s(16) #16 means change to hax format
       
          if msgtype == 0x01 #0x01 is noise message
            datatype="noise"#my variable
            data = params[:data].unpack("f") #unpack data from 0 and 1s
            data = data.blank? ? -1 : data.first.round(2) #this is where data is stored.add a check point here
            noise_devices_set = NoiseDevice.where(serial_number: serial)  #deal with which device,this serial number as device id
            
            if noise_devices_set.count > 0
              noise_device = noise_devices_set.first    
		#noise device number assigned here!!!!!!!!!!
              
              if noise_device.project.blank?
                render json: { error: "Noise device is not in a project" }
                return nil
              end
              
              if noise_device.project.status == "Ongoing"
                noise_device.noise_data.create project_id: noise_device.project.id, leq: data, received_at: time #noise value assigned here !!!!!!!!!!!!!
                
                datavalue=data#my variable
                projectid=noise_device.project.id #my variable
                
                render json: { status: true }
              else
                render json: { error: "Project is not currently running" }
              end
            else
              render json: { error: "Noise device is not available" }
            end
          elsif msgtype == 0x02  #Vibration message 1 (event based) 
            datatype="vibration"
            trigger_value = data[4]

            
            vibration_devices_set = VibrationDevice.where(serial_number: serial)
            
            if vibration_devices_set.count > 0
              vibration_device = vibration_devices_set.first  #virbration device number set here 
              
              if vibration_device.project.blank?
                render json: { error: "Vibration device is not in a project" }
                return nil
              end
              
              if vibration_device.project.status == "Ongoing"
                if vibration_device.current_trigger_value != trigger_value
                  vibration_device.update_attributes current_trigger_value: trigger_value
                end
                
                vibration_device.vibration_data.create project_id: vibration_device.project.id, r_velocity: data[5].round(2),
                                                       r_frequency: data[6].round(2), v_velocity: data[7].round(2),
                                                       v_frequency: data[8].round(2),t_velocity: data[9].round(2),
                                                       t_frequency: data[10].round(2), received_at: time,
                                                       value_type: "event", plot_data: params[:data] #virbration data is assigned here
                #datavalue=                    (to be decided here)
                
                render json: { status: true }
              else
                render json: { error: "Project is not currently running" }
              end
            else
              render json: { error: "Vibration device is not available" }
            end
          elsif msgtype == 0x03 #Vibration message2(Continuous based)
            data = params[:data].unpack("fff")
            
            vibration_devices_set = VibrationDevice.where(serial_number: serial)
            
            if vibration_devices_set.count > 0
              vibration_device = vibration_devices_set.first
              
              if vibration_device.project.blank?
                render json: { error: "Vibration device is not in a project" }
                return nil
              end
              
              if vibration_device.project.status == "Ongoing"
                vibration_device.vibration_data.create project_id: vibration_device.project.id, r_velocity: data[0].round(2),
                                                       v_velocity: data[1].round(2), t_velocity: data[2].round(2), received_at: time,
                                                       value_type: "continuous"
                
                render json: { status:true}
              else
                render json: { error: "Project is not currently running" }
              end
            else
              render json: { error: "Vibration device is not available" }
            end
          end
        end
      else
        render json: { error: "CRC32 does not match" }
      end
    else
      render json: { error: "Not enough parameters in the request" }
    end
#################################origional code input end here
     
if datatype=="noise" && !datavalue.nil? #datatype is noise 
	@exceed||=false
	hourtocompare=timeforcheck.strftime("%H").to_i
       if not timeforcheck.wday==0  #if not sunday

         if hourtocompare>19 && hourtocompare<22#19 to 22

           if datavalue > 70
             @exceed=true #7 to 22,the noise exceed	 
           end
    
         elsif(hourtocompare>22 && hourtocompare<24) || (hourtocompare>0 && hourtocompare<7)   #10pm to 7am

              if datavalue>55
                @exceed=true #between 10pm to 7am,exceed
              end

      	 elsif hourtocompare>7 && hourtocompare<19#7 to 19
     if datavalue>90
                @exceed=true #7am to 7 pm,noise exceed
              end
         end #for if timeforcheck.hour>19
       end #for check not sunday

       elsif timeforcheck.wday==0 #the day is sunday

            if hourtocompare>7 && hourtocompare<19
              if datavalue>75
                @exceed=true  
		#noise has exceed 75db,at7am-7pm,sunday
              end     
            else
              if datavalue>55     
		#noise has exceed 55db,7pm to 7 am,sunday
                @exceed=true
       	      end
            end #this end is for if timeforcheck.hour>7
        end #this end is for sunday check     
	
	if @exceed==false #false means not exceed range
	 render json: {error: "or testing"}#for testing
 	end
	if @exceed==true  #exceed range
	 
  	if @@flagtime >= DateTime.now
	#do sth here? last sms is send within an hour
	elsif @@flagtime < DateTime.now 
	contact1=Contact.where(:project_id=>projectid).first.phone_number
        project=projectid.to_s
        value=datavalue.to_s
        time=timeforcheck.strftime("%H:%M,%b%d,%Y")
        type=datatype.to_s
	serialno=serial.to_s.upcase
	clientname=noise_device.project.client_name
	clienttest=Project.where(id=projectid)
	jobnumber=noise_device.project.job_number
	@msg1="Dear #{clientname},Your Project #{jobnumber},#{type} device #{serialno} reading is #{value}.exceed limit at #{time}"
        user="geoscanx"      #secure? login info for sms service
        password="tampinesx" #secure? login info for sms service
        option="send"
        @towhom=contact1
      uri=URI("http://www.sms.sg/http/sendmsg")
      params={ :user=>user,:pwd=>password,:option=>option,:to=>@towhom,:msg=>@msg1}
	uri.query=URI.encode_www_form(params)
      file=open(uri)
      contents=file.read
	@@flagtime=@@flagtime+1.hours
	#if (contents.downcase.include? "ok".downcase) #sms.sg ok
	#if (contents.downcase.include? "Err".downcase)#sms.sg Err


        end#end for time compare

	end  #if @exceed

      #this method will check if value exceed our limit
end #for datatype=noise checkexceed
#########################################################
##########following is sms send function#################
#'http://www.sms.sg/http/sendmsg?user=xxxxx&pwd=xxxxx&option=send&to=83576637&msg=Test1'



##############end of sms send function####################
##########################################################



def smsmessage
    if !params[:msg]=nil & Contact.phone_number.include?(params[:from])   
    #check if message is null,and if sender is inside our user list
       @blocks=Hash.new
       hour=params[:msg].to_i  rescue nil
      if hour<24 and hour>1
      sendtime=param[:datetime] #param[datetime] is nearly time.now,its realtime
      trimtime=sendtime+hour.hours
      @blocks[params[:from]]=trimtime 
      #write to hash,this user's message is blocked until this trimtime
      end
    end
  end #this method will handle replied sms message



  private
    def verify_data summary, data, crc32_code
      true
    end
end#this is the end for input method
