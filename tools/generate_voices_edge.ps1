# generate_voices_edge.ps1 — Windows PowerShell equivalent of generate_voices_edge.sh
# Usage:
#   powershell tools\generate_voices_edge.ps1 en-US-AriaNeural female
#   powershell tools\generate_voices_edge.ps1 en-US-GuyNeural male

param(
    [string]$Voice  = "en-US-AriaNeural",
    [string]$Gender = "female"
)

$Out = "assets\voice\$Gender"
New-Item -ItemType Directory -Force -Path $Out | Out-Null

function Gen($Slug, $Line) {
    Write-Host "  $Slug  <-  `"$Line`""
    python -m edge_tts --voice $Voice --text $Line --write-media "$Out\$Slug.mp3" 2>$null
}

Write-Host "Generating NPC voice clips ($Voice) into $Out\ ..."
Gen "yes"               "Yes?"
Gen "hello"             "Hello!"
Gen "hi_there"          "Hi there!"
Gen "good_morning"      "Good morning!"
Gen "hey"               "Hey!"
Gen "see_you"           "See you!"
Gen "take_care"         "Take care!"
Gen "goodbye"           "Goodbye!"
Gen "anytime_good_luck" "Anytime, good luck!"
Gen "im_fine"           "I'm fine!"
Gen "im_good"           "I'm good!"
Gen "im_great_thanks"   "I'm great, thanks!"
Gen "sorry_dont_know"   "Sorry, I don't know that place."
Gen "its_over_there"    "It's over there!"

Write-Host "Done. Files in $Out\. Now run: bash deploy.sh `"add voice sets`""
