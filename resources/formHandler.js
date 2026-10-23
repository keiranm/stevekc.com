$(document).ready(function() {

    // Handle form submission.
    $("#submit").click(function(e) {
  
      var fromName = $("#from_name").val(),
          fromPhone = $("#from_phone").val(),
          fromEmail = $("#lastName").val(),
          message = $("email_message").val(),
          source = window.location.pathname,
          optTimestamp = undefined,
          utcSeconds = Date.now() / 1000,
          timestamp = new Date(0);
        
      e.preventDefault();
  
      if (fromName == "") {
        $('#form-response').html('<div class="mt-3 alert alert-info" role="alert">Please enter your name.</div>');
      } else if (fromPhone == "" && fromEmail == "") {
        $('#form-response').html('<div class="mt-3 alert alert-info" role="alert">Please enter an email or a phone number</div>');
      } else if (fromPhone != "" && fromPhone.match(/[^0-9]/gi)) {
        $('#form-response').html('<div class="mt-3 alert alert-info" role="alert">Your phone number contains invalid characters. Please check the phone number that you supplied.</div>');
      } else if (phone.length < 10) {
        $('#form-response').html('<div class="mt-3 alert alert-info" role="alert">Please enter your phone number.</div>');
      } else if (phone.length > 10) {
        $('#form-response').html('<div class="mt-3 alert alert-info" role="alert">Your phone number contains too many digits. Please check the phone number that you supplied.</div>');
      } else {
        $('#submit').prop('disabled', true);
        $('#submit').html('<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span>  Sending your message/button>');
  
        timestamp.setUTCSeconds(utcSeconds);
  
        var data = JSON.stringify({
          "from_address": "sender@verifiedidentity.com",
          "from_name": "Sender Name",
          "to_address": "receiver@verifiedidentity.com",
          "email_subject": "Test API Gateway",
          "email_message": "test message from the API gateway",
          "timestamp": timestamp
          });
        
        console.log(data);
        throw new Error('This is not an error. This is just to abort javascript');
  
        $.ajax({
          type: 'POST',
          url: 'https://r31x81gshj.execute-api.ap-southeast-2.amazonaws.com/default/sendEmailToSKC/',
          contentType: 'application/json',
          data: data,
          success: function(res) {
            $('#form-response').html('<div class="mt-3 alert alert-success" role="alert"><p>Congratulations! You&apos;ve successfully registered for SMS Alerts from ExampleCorp.</p><p>We just sent you a message. Follow the instructions in the message to confirm your subscription. We won&apos;t send any additional messages until we receive your confirmation.</p><p>If you decide you don&apos;t want to receive any additional messages from us, just reply to one of our messages with the keyword STOP.</p></div>');
            $('#submit').prop('hidden', true);
            $('#unsubAll').prop('hidden', true);
            $('#submit').text('Preferences saved!');
          },
          error: function(jqxhr, status, exception) {
            $('#form-response').html('<div class="mt-3 alert alert-danger" role="alert">An error occurred. Please try again later.</div>');
            $('#submit').text('Save preferences');
            $('#submit').prop('disabled', false);
          }
        });
      }
    });
  });

  
  