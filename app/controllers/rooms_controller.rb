class RoomsController < ApplicationController
  before_action :set_room, only: [:show, :edit, :update, :destroy, :user_exit_room, :is_user_ready, :chat, :open_chat]
  before_action :authenticate_user!, except: [:index]

  layout "chat", only: [:chat, :open_chat]

  # GET /rooms
  # GET /rooms.json
  def index
    @rooms = Room.where(room_state: false).all
    @rooms.where(admissions_count: 0).destroy_all
  end

  # GET /rooms/1
  # GET /rooms/1.json
  def show
   
    respond_to do |format|
      if @room.chat_started?
       format.html { render 'chat', layout: false}
      else
        if @room.max_count > @room.admissions_count
          @room.user_admit_room(current_user) unless current_user.joined_room?(@room)  
          format.html { render 'show' }
        else
          if @room.admissions.exists?(user_id: current_user.id)
            format.html { render 'show' }
          else
            format.html {render 'alert'}
          end  
        end      
      end
    end

  end

  # GET /rooms/new
  def new
    @room = Room.new
  end

  # GET /rooms/1/edit
  def edit
  end

  # POST /rooms
  # POST /rooms.json
  def create
   @room = Room.new(room_params)
   @room.master_id = current_user.email
   

   
   respond_to do |format|
      if @room.save
       @room.user_admit_room(current_user) #room.rb
       p "create의 user_admit_room 실행"
       format.html { redirect_to @room, notice: 'Room was successfully created.' }
       format.json { render :show, status: :created, location: @room }
      else
       format.html { render :new }
       format.json { render json: @room.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /rooms/1
  # PATCH/PUT /rooms/1.json
  def update
    respond_to do |format|
      if @room.update(room_params)
        format.html { redirect_to @room, notice: 'Room was successfully updated.' }
        format.json { render :show, status: :ok, location: @room }
      else
        format.html { render :edit }
        format.json { render json: @room.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /rooms/1
  # DELETE /rooms/1.json
  def destroy
    @room.destroy
    respond_to do |format|
      format.html { redirect_to rooms_url, notice: 'Room was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  def sign_up
  end
  
  def user_create
      @user = User.create(email: params[:email], password: params[:password], nickname: params[:nickname], major: params[:major], another_major: params[:another_major], sex: params[:sex])
      ContactMailer.contact_mail(@user).deliver_now
      redirect_to "/users/sign_in"
  end

  def sign_in
  end
  
  def log_in
    # 유저가 입력한 ID, PW를 바탕으로
    # 실제로 로그인이 이루어지는 곳
    if user_signed_in?
      redirect_to '/'
    else
      # 가입한 user_id가 없거나, 패스워드가 틀린경우
      redirect_to '/users/sign_in'
    end
  end
  
  def logout
    session.delete(:current_user)
    redirect_to '/'
  end

  ### 채팅 ###
  def user_exit_room
    p "유저나가기 컨트롤러까지는 옴"
    @room.user_exit_room(current_user)
    # @room.zero_room_delete(current_user)
    if @room.room_state 
      @room.update(room_state: false)
    end
  end
  
  def is_user_ready
   if current_user.is_ready?(@room) # 현재 레디상태라면
     render js: "console.log('이미 레디상태'); location.reload();"
   else  # 현재 레디상태가 아니라면
     @room.user_ready(current_user) # 현재유저의 레디상태 바꿔주기
     render js: "console.log('레디상태로 바뀌었습니다.'); location.reload();"
     # 현재 레디한 방 외에 모든방의 레디해제
     current_user.admissions.where.not(room_id: @room.id).destroy_all
     # if
   end
   
  end
 
  def chat
    @room_id = @room.id
    @room.chats.create(user_id: current_user.id, message: params[:message])
  end
 
  def open_chat
   @room.update(room_state: true)
   @room.admissions.each do |admission|
      UserChatLog.create(room_title: @room.room_title, room_id: @room.id, user_id: admission.user_id, nickname: admission.user.nickname, chat_date: admission.updated_at.to_date )
   end

   Pusher.trigger("room_#{@room.id}", 'chat_start', {})
  
   RoomDestroyJob.set(wait: 1.hour).perform_later(@room.id) # 한시간 뒤에 방을 폭파하는 코드.
  end
 
  def hashtags
    tag = Tag.find_by(name: params[:name])
    @rooms = tag.rooms
    @tag =tag.name
  end

  def search
    if params[:hashsearch] and params[:room_type] and params[:food_type]
      @rooms = Room.where("room_title LIKE ?", "%#{params[:hashsearch]}%").where(room_type: params[:room_type], food_type: params[:food_type]).to_a 
    elsif params[:food_type] and params[:room_type]
      @rooms = Room.where(food_type: params[:food_type], room_type: params[:room_type]).to_a
    elsif params[:hashsearch] and params[:room_type]
      @rooms = Room.where("room_title LIKE ?", "%#{params[:hashsearch]}%").where(room_type: params[:room_type]).to_a 
    elsif params[:hashsearch] and params[:food_type]
      @rooms = Room.where("room_title LIKE ?", "%#{params[:hashsearch]}%").where(food_type: params[:food_type]).to_a 
    elsif params[:hashsearch]
      @rooms = Room.where("room_title LIKE ?", "%#{params[:hashsearch]}%").to_a
    elsif params[:food_type]
      @rooms = Room.where(food_type: params[:food_type]).to_a
    elsif params[:room_type]
      @rooms =  Room.where(room_type: params[:room_type]).to_a
    end
  end
  
  def quickmatch
  end
  
  def matching
    # 해당하는 방이 없을 때, alert를 띄우던지 아니면 해당하는 방이 없다는 화면으로 보내주던지...
    if !Room.where(room_type: "먹방").to_a[0].nil?
      match_num = 0
      if Room.where(room_type: "먹방").size > 1
        while match_num < Room.where(room_type: "먹방").to_a.length
          if Room.where(room_type: "먹방").order(admissions_count: :desc)[match_num].admissions_count < Room.where(room_type: "먹방").order(admissions_count: :desc)[match_num].max_count
            @rooms = Room.where(room_type: "먹방").order(:admissions_count).reverse.sort[match_num].id 
            # 룸타입이 먹방인 방에서, 현재 인원의 역순으로 정렬후, 인덱스에 따라서 다시 정렬, 그후 id만 추출
            redirect_to "/rooms/#{@rooms}"
          break
          else
            match_num += 1
          end
        end
      else
        if Room.where(room_type: "먹방")[0].admissions_count == Room.where(room_type:"먹방")[0].max_count
          flash[:danger] = "매치할 방이 없습니다..방을 직접 만들거나 잠시후 다시 시도해주세요!"
          redirect_to quickmatch_path
        else
          @rooms = Room.where(room_type: "먹방")[0].id 
          # 룸타입이 먹방인 방에서, 현재 인원의 역순으로 정렬후, 인덱스에 따라서 다시 정렬, 그후 id만 추출
          redirect_to "/rooms/#{@rooms}"
        end
      end
    else
      flash[:danger] = "매치할 방이 없습니다..방을 직접 만들거나 잠시후 다시 시도해주세요!"
      redirect_to quickmatch_path
    end  
  end

  def report
    @report = Report.new
  end
   
  def report_create
      p "신고받음"
      @report = Report.create(report_reason: params[:report_reason], report_description: params[:report_description])
      @report.user_id = current_user.id
      @report.user_email = current_user.email
  end


  private
    # Use callbacks to share common setup or constraints between actions.
    def set_room
      @room = Room.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def room_params
      @room = params.require(:room).permit(:room_title, :max_count, :room_state, :admissions_count, :meet_time_end, :start_time_hour, :start_time_min, :food_type, :room_type, :hashtag)
    # {room_title: params[:room][:room]
    end
    
    # def user_params
    #   #email: params[:email], password: params[:password], nickname: params[:nickname], major: params[:major], another_major: params[:another_major], sex: params[:sex]
    #   @user = params.require(:user).permit(:email, :password, :nickname, :major, :another_major. :sex)
    # end
end


 