// JavaScript code to handle the search bar and character selection
const searchBar = document.getElementById('search-bar');
const searchResults = document.getElementById('search-results');
const previousPicksList = document.getElementById('previous-picks-list');
const congratulationsRectangle = document.getElementById('congratulations-rectangle');
const overlay = document.getElementById('overlay');
const closeBtn = document.getElementById('close-btn');
let selectedCharacters = [];
let correctCharacterPicked = false; // Flag to track if the correct character is picked

// Array to keep track of characters that are selected
let availableCharacters = []; // New array to keep track of available characters

searchBar.addEventListener('input', function() {
    const query = searchBar.value.trim();

    // If the correct character has already been picked, stop further input
    if (correctCharacterPicked) {
        return;
    }

    if (query) {
        fetch(`/search_characters?query=${query}`)
            .then(response => response.json())
            .then(data => {
                // Filter out characters that are already selected
                const filteredData = data.filter(item => !selectedCharacters.includes(item.chr_name));
                searchResults.innerHTML = ''; // Clear previous results

                filteredData.forEach(item => {
                    const resultItem = document.createElement('div');
                    resultItem.className = 'result-item';
                    resultItem.innerHTML = `<img src="https://bleach-web.s3.eu-north-1.amazonaws.com/static/images/${item.chr_name.toLowerCase().replace(/\s+/g, '_')}.png" alt="${item.chr_name}"> ${item.chr_name}`;
                    resultItem.addEventListener('click', function() {
                        selectCharacter(item.chr_name);
                    });
                    searchResults.appendChild(resultItem);
                });

                searchResults.style.display = 'block';
            });
    } else {
        searchResults.style.display = 'none';
    }
});

function selectCharacter(characterName) {
// Add character to selected list
selectedCharacters.push(characterName);

// Add the selected character to the previous picks list
fetch('/compare_bankai', {
method: 'POST',
headers: { 'Content-Type': 'application/json' },
body: JSON.stringify({ selected_character: characterName })
})
.then(response => response.json())
.then(data => {
if (data.error) {
    alert(data.error);
    return;
}

const previousPickDiv = document.createElement('div');
previousPickDiv.className = 'previous-pick';

// Check if the selected character's chr_id matches today's Bankai's chr_id
const isCorrect = data.is_correct;

// Construct the HTML for the character's data
let attributesHTML = `
        <img src="https://bleach-web.s3.eu-north-1.amazonaws.com/static/images/${data.character_data.chr_name.toLowerCase().replace(/\s+/g, '_')}.png" class="character-image" alt="${data.character_data.chr_name}" style="opacity: 0;">
        <div class="name-box ${isCorrect ? 'green' : 'red'}" style="opacity: 0;">${data.character_data.chr_name}</div>`;


previousPickDiv.innerHTML = attributesHTML;

// Prepend the new pick to the top of the list
previousPicksList.prepend(previousPickDiv);

// Animate the appearance of the image, name
animateBoxes(previousPickDiv);

// If the character picked is correct, stop further input and hide the search bar
if (isCorrect) {
    correctCharacterPicked = true;
    searchBar.disabled = true; // Disable search input
    searchBar.value = ''; // Clear search input
    searchResults.style.display = 'none'; // Hide search results
    searchBar.style.display = 'none'; // Hide the search bar

    // Show the congratulations popup and overlay
    congratulationsRectangle.style.display = 'flex';
    overlay.style.display = 'block';

    // Start the countdown timer to midnight
    startCountdown();
}
});

// Hide the selected character from the search list
searchBar.value = '';
searchResults.style.display = 'none';
}



function animateBoxes(previousPickDiv) {
// Get all the elements to animate (image, name, and attribute boxes)
const imageBox = previousPickDiv.querySelector('.character-image');
const nameBox = previousPickDiv.querySelector('.name-box');
// Delay time in milliseconds between each box's appearance
let delayTime = 0;

// Animate the image box first
setTimeout(() => {
imageBox.style.transition = 'opacity 1s ease'; // Add transition for fading in
imageBox.style.opacity = 1; // Make the image box visible
}, delayTime);

// Increase delay for the next element
delayTime += 500; // Delay of 500ms for the name box

// Animate the name box next
setTimeout(() => {
nameBox.style.transition = 'opacity 1s ease'; // Add transition for fading in
nameBox.style.opacity = 1; // Make the name box visible
}, delayTime);

}



// Countdown timer to midnight
function startCountdown() {
    const countdownDisplay = document.getElementById('countdown-timer');
    const currentDate = new Date();
    const nextMidnight = new Date();
    nextMidnight.setHours(24, 0, 0, 0);  // Set next midnight

    function updateCountdown() {
        const now = new Date();
        const timeRemaining = nextMidnight - now;

        if (timeRemaining <= 0) {
            countdownDisplay.innerHTML = '00:00:00';
            clearInterval(countdownInterval); // Stop the countdown
        } else {
            const hours = Math.floor(timeRemaining / (1000 * 60 * 60));
            const minutes = Math.floor((timeRemaining % (1000 * 60 * 60)) / (1000 * 60));
            const seconds = Math.floor((timeRemaining % (1000 * 60)) / 1000);
            countdownDisplay.innerHTML = `${formatTime(hours)}:${formatTime(minutes)}:${formatTime(seconds)}`;
        }
    }

    // Helper function to format time values (adding leading zero)
    function formatTime(time) {
        return time < 10 ? '0' + time : time;
    }

    // Update the countdown every second
    const countdownInterval = setInterval(updateCountdown, 1000);
}
// Close search results if clicked outside the search bar or results, and clear the search bar
document.addEventListener('click', function(event) {
    if (!searchBar.contains(event.target) && !searchResults.contains(event.target)) {
        searchResults.style.display = 'none';
        searchBar.value = ''; // Clear the search bar when clicked outside
    }
});
// Event listener for the close button
closeBtn.addEventListener('click', function() {
// Hide the congratulations rectangle and the overlay when clicked
congratulationsRectangle.style.display = 'none';
overlay.style.display = 'none';
});

// Get the current path from the URL
const currentPath = window.location.pathname;

// Select all circles
const circles = document.querySelectorAll('.circlee');

// Loop through each circle
circles.forEach(circle => {
// Get the href value of the anchor
const circlePath = circle.getAttribute('href');

// Apply styles based on the current path
if (circlePath === currentPath) {
// Add gold glow to the current circle
circle.classList.add('gold-glow');
} else {
// Set gray border for other circles
circle.classList.add('gray-border');
}
});