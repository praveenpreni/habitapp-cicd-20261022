package com.example.habittracker.service;

import com.example.habittracker.dto.HabitRequest;
import com.example.habittracker.model.Habit;
import com.example.habittracker.repository.HabitRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import static org.assertj.core.api.Assertions.*;

class HabitServiceTests {
    private HabitService service;
    private static final LocalDate TODAY = LocalDate.of(2026, 10, 22);

    @BeforeEach void setup() {
        service = new HabitService(new HabitRepository(),
            Clock.fixed(Instant.parse("2026-10-22T06:00:00Z"), ZoneOffset.UTC));
    }
    private Habit create() {
        HabitRequest request = new HabitRequest();
        request.setName("Read");
        request.setDescription("Read a book");
        return service.create(request);
    }
    @Test void createsListsUpdatesAndDeletes() {
        Habit habit = create();
        assertThat(habit.getCreatedDate()).isEqualTo(TODAY);
        assertThat(service.getAll()).extracting(Habit::getName).containsExactly("Read");
        HabitRequest changed = new HabitRequest();
        changed.setName("Walk"); changed.setDescription("Outside");
        changed.setFrequency(Habit.Frequency.WEEKLY);
        assertThat(service.update(habit.getId(), changed).getFrequency())
            .isEqualTo(Habit.Frequency.WEEKLY);
        assertThat(service.getById(habit.getId()).getName()).isEqualTo("Walk");
        assertThat(service.setActive(habit.getId(), false).isActive()).isFalse();
        service.delete(habit.getId());
        assertThat(service.getAll()).isEmpty();
    }
    @Test void missingReadUpdateAndDeleteThrowNotFound() {
        assertThatThrownBy(() -> service.getById(99L)).isInstanceOf(HabitNotFoundException.class);
        assertThatThrownBy(() -> service.update(99L, new HabitRequest()))
            .isInstanceOf(HabitNotFoundException.class);
        assertThatThrownBy(() -> service.delete(99L)).isInstanceOf(HabitNotFoundException.class);
    }
    @Test void duplicateCompletionsAreIdempotent() {
        Long id = create().getId();
        service.markComplete(id, null); service.markComplete(id, null);
        assertThat(service.getById(id).getCompletedDates()).containsExactly(TODAY);
        assertThat(service.getStats(id).getTotalCompletions()).isEqualTo(1);
        assertThat(service.getStats(id).getLast7DaysCompletionRate()).isEqualTo(14.3);
    }
    @Test void streakCountsConsecutiveDatesAndBreaksOnGaps() {
        Long id = create().getId();
        for (int days : new int[]{7, 6, 5, 2, 1, 0}) service.markComplete(id, TODAY.minusDays(days));
        assertThat(service.getStats(id).getCurrentStreak()).isEqualTo(3);
        assertThat(service.getStats(id).getLongestStreak()).isEqualTo(3);
        service.unmarkComplete(id, TODAY.minusDays(1));
        assertThat(service.getStats(id).getCurrentStreak()).isEqualTo(1);
        assertThat(service.getStats(id).getLongestStreak()).isEqualTo(3);
    }
    @Test void oldCompletionsDoNotCountAsCurrentStreak() {
        Long id = create().getId(); service.markComplete(id, TODAY.minusDays(3));
        assertThat(service.getStats(id).getCurrentStreak()).isZero();
        assertThat(service.getStats(id).getLongestStreak()).isEqualTo(1);
    }
    @Test void yesterdayCountsAsCurrentStreak() {
        Long id = create().getId(); service.markComplete(id, TODAY.minusDays(1));
        assertThat(service.getStats(id).getCurrentStreak()).isEqualTo(1);
    }
    @Test void removingLastCompletionResetsStreaks() {
        Long id = create().getId(); service.markComplete(id, null); service.unmarkComplete(id, null);
        assertThat(service.getStats(id).getCurrentStreak()).isZero();
        assertThat(service.getStats(id).getLongestStreak()).isZero();
        assertThat(service.getStats(id).getLast7DaysCompletionRate()).isZero();
    }
    @Test void nullFrequencyOnUpdateKeepsExistingFrequency() {
        Long id = create().getId(); HabitRequest changed = new HabitRequest();
        changed.setName("Run"); changed.setFrequency(null);
        assertThat(service.update(id, changed).getFrequency()).isEqualTo(Habit.Frequency.DAILY);
    }
}
