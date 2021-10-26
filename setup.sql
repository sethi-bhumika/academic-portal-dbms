/*
 the aim of this file is to setup the schemas and tables,
 create cleanup functions, startup functions and
 populate the tables with some dummy data as well.
 */


/*
 delete all previous schemas, tables and data to start off with a clean database
 */
drop schema if exists
    academic_data,
    course_offerings,
    student_grades,
    registrations
    cascade;

/*
 create the required schemas which will have tables and some custom dummy data
 */
create schema academic_data; -- for general academic data
create schema admin_data;
create schema course_offerings; -- for course offered in the particular semester and year
create schema student_grades; -- for final grades of the student for all the courses taken to generate C.G.P.A.
create schema registrations;
-- will contain information regarding student registration and tickets

-- five departments considered, can be scaled up easily
create table academic_data.departments
(
    dept_name varchar primary key
);

-- stores current 
create table academic_data.semester
(
    semester integer not null,
    year integer not null,
    primary key (semester, year)
);


grant select on academic_data.semester to PUBLIC;

insert into academic_data.departments (dept_name)
values ('cse'), -- computer science and engineering
       ('me'), -- mechanical engineering
       ('ee'), -- civil engineering
       ('ge'), -- general
       ('sc'), -- sciences
       ('hs') -- humanities
;

-- undergraduate curriculum implemented only
create table academic_data.degree
(
    degree varchar primary key
);
insert into academic_data.degree
values ('btech'); -- bachelors degree only

create table academic_data.course_catalog
(
    course_code        varchar primary key,
    dept_name          varchar not null,
    credits            real not null,
    credit_structure   varchar not null,
    course_description varchar   default '',
    pre_requisites     varchar[] default '{}',
    foreign key (dept_name) references academic_data.departments (dept_name)
);

-- todo: populate course catalog with dummy data from csv file
create table academic_data.student_info
(
    roll_number  varchar primary key,
    student_name varchar not null,
    department   varchar not null,
    batch_year   integer not null,
    foreign key (department) references academic_data.departments (dept_name),
    foreign key (degree) references academic_data.degree (degree)
);
-- todo: populate student info with dummy list of students from csv file

create table academic_data.faculty_info
(
    faculty_id   varchar primary key,
    faculty_name varchar not null,
    department   varchar not null,
    foreign key (department) references academic_data.departments (dept_name)
);
-- todo: populate faculty info with dummy list of faculties from csv file

-- create table academic_data.advisers
-- (
--     faculty_id varchar primary key,
--     batches    integer[] default '{}', -- format batch_year, assumed to be of their own department
--     foreign key (faculty_id) references academic_data.faculty_info (faculty_id)
-- );
create table academic_data.ug_batches
(
    dept_name varchar,
    batch_year integer,
    adviser_f_id varchar
    PRIMARY KEY (dept_name, batch_year)
);
-- TODO: populate with some random faculties acting as advisers from available faculties

create or replace function course_offerings.add_new_semester(academic_year integer, semester_number integer)
    returns void as
$function$
declare
    -- iterator to run through all the faculties' ids
    faculty_cursor cursor for select faculty_id
                              from academic_data.faculty_info;
    declare f_id         academic_data.faculty_info.faculty_id%type;
    declare adviser_f_id academic_data.faculty_info.faculty_id%type;
    declare student_cursor for select roll_number from academic_info.student_info;
    declare s_rollnumber academic_data.student_info.roll_number%type;
begin
    -- assuming academic_year = 2021 and semester_number = 1
    -- will create table course_offerings.sem_2021_1 which will store the courses being offered that semester
    execute ('create table course_offerings.sem_' || academic_year || '_' || semester_number || '
                (
                    course_code     varchar primary key,
                    instructors     varchar[] not null,
                    slot            varchar,
                    allowed_batches varchar[] not null, -- will be combination of batch_year and department: cse_2021
                    foreign key (course_code) references academic_data.course_catalog (course_code)
                );'
        );

    -- will create table registrations.provisional_course_registrations_2021_1
    -- to be deleted after registration window closes
    -- to store the list of students interest in taking that course in that semester
    -- whether to allow or not depends on various factors and
    -- if accepted, then will be saved to registrations.{course_code}_2021_1
    execute ('create table registrations.provisional_course_registrations_' || academic_year || '_' || semester_number || '
                (   
                    roll_number     varchar not null,
                    course_code     varchar ,
                    foreign key (course_code) references academic_data.course_catalog (course_code),
                    foreign key (roll_number) references academic_data.student_info (roll_number)
                );'
        );

    -- all tickets generated by students will be stored here
    execute ('create table registrations.student_ticket_' || academic_year || ' ' || semester_number ||
                 ' (
                     roll_number varchar not null,
                     course_code varchar not null,
                     status boolean,
                     foreign key (course_code) references academic_data.course_catalog (course_code),
                     foreign key (roll_number) references academic_data.student_info (roll_number)
                 )'
            );
    
    open student_cursor;
    loop
        fetch student_cursor into s_rollnumber;
        exit when not found;
        execute('grant select on course_offerings.sem_'||academic_year||'_'||semester_number||' to '||s_rollnumber||';');
        execute('grant insert on course_offerings.provisional_course_registrations_'||academic_year||'_'||semester_number||' to '||s_rollnumber||';');
        execute('grant insert on registrations.student_ticket_'||academic_year||'_'||semester_number||' to '||s_rollnumber||';');
    end loop;
    close student_cursor;

    execute('create table admin_data.dean_tickets_'||academic_year||'_'||semester_number||
       ' roll_number varchar not null,
        course code varchar not null,
        dean_decision boolean,
        faculty_decision boolean,
        student_decision boolean,
        foreign key (course_code) references academic_data.course_catalog (course_code),
        foreign key (roll_number) references academic_data.student_info (roll_number)
    ');

    open faculty_cursor;
    loop
        fetch faculty_cursor into f_id;
        exit when not found;
        -- store the tickets for a faculty in that particular semester
        execute ('create table registrations.faculty_ticket_' || f_id || '_' || academic_year || ' ' ||
                 semester_number ||
                 ' (
                     roll_number varchar not null,
                     course_code varchar not null,
                     status boolean,
                     foreign key (course_code) references academic_data.course_catalog (course_code),
                     foreign key (roll_number) references academic_data.student_info (roll_number)
                 )'
            );
        execute('grant select on registrations.student_ticket_'||academic_year||'_'||semester_number||' to '||f_id||';');
        execute('grant all privileges on registrations.faculty_ticket_' || f_id || '_' || academic_year || ' ' ||semester_number ||' to '||f_id||';');
        execute('grant insert on course_offerings.sem_'||academic_year||'_'||semester_number||' to '||f_id||';');
        -- check if that faculty is also an adviser
        select academic_data.ug_batches.adviser_f_id from academic_data.ug_batches where f_id = academic_data.ug_batches.adviser_f_id into adviser_f_id;
        if adviser_f_id != '' then
            -- store the tickets for a adviser in that particular semester
            execute ('create table registrations.adviser_ticket_' || f_id || '_' || academic_year || ' ' ||
                     semester_number ||
                     ' (
                         roll_number varchar not null,
                         course_code varchar not null,
                         status boolean,
                         foreign key (course_code) references academic_data.course_catalog (course_code),
                         foreign key (roll_number) references academic_data.student_info (roll_number)
                     )'
                );
            execute('grant all privileges on registrations.adviser_ticket_' || f_id || '_' || academic_year || ' ' ||semester_number ||' to '||f_id||';');
        end if;
    end loop;
    close faculty_cursor;

end;
$function$ language plpgsql;

create or replace procedure admin_data.create_student(roll_number varchar)
    language plpgsql as
$function$
begin
    create user roll_number password roll_number;
    execute ('create table student_grades.student_' || roll_number || '
                (
                    course_code     varchar not null,
                    semester        integer not null,
                    year            integer not null,
                    grade           integer not null default ''0'',
                    foreign key (course_code) references academic_data.course_catalog (course_code)
            );' ||
             'grant select on student_grades.student_' || roll_number || ' to ' || roll_number || ';'
        );
    grant select on academic_data.course_catalog to roll_number;
    grant select on academic_data.student_info to roll_number;
    grant select on academic_data.faculty_info to roll_number;
    grant select on academic_data.departments to roll_number;
end;
$function$;

-- todo: to be added to the dean actions later so that only dean's office creates new students
create trigger generate_student_record
    after insert
    on academic_data.student_info
    for each row
execute procedure admin_data.create_student(new.roll_number);

-- creating a faculty
create or replace procedure admin_data.create_faculty(faculty_id varchar)
    language plpgsql as
$function$
declare
begin
    create user faculty_id password faculty_id;
    grant select on academic_data.course_catalog to faculty_id;
    grant select on academic_data.student_info to faculty_id;
    grant select on academic_data.faculty_info to faculty_id;
    grant select on academic_data.departments to faculty_id;
end;
$function$;

-- todo: to be added to the dean actions later so that only dean's office creates new students
create trigger generate_faculty_record
    after insert
    on academic_data.faculty_info
    for each row
execute procedure admin_data.create_faculty(new.faculty_id);

-- get the credit limit for a given roll number
create or replace function get_credit_limit(roll_number varchar)
    returns real as
$$
declare
    grades_list         table
                        (
                            course_code varchar,
                            semester    integer,
                            year        integer,
                            grade       integer
                        );
    current_semester    integer;
    current_year        integer;
    course_code         varchar;
    courses_to_consider varchar[];
    credits_taken       real;
begin
    execute ('select * from student_grades.student_' || roll_number || ' into grades_list;');
    select semester from academic_data.semester into current_semester;
    select year from academic_data.semester into current_year;
    if current_semester = 2
    then
        -- even semester
        courses_to_consider = array_append(courses_to_consider, (select grades_list.course_code
                                                                 from grades_list
                                                                 where grades_list.semester = 1
                                                                   and grades_list.year = current_year));
        courses_to_consider = array_append(courses_to_consider, (select grades_list.course_code
                                                                 from grades_list
                                                                 where grades_list.semester = 2
                                                                   and grades_list.year = current_year - 1));
    else
        -- odd semester
        courses_to_consider = array_append(courses_to_consider, (select grades_list.course_code
                                                                 from grades_list
                                                                 where grades_list.semester = 1
                                                                   and grades_list.year = current_year - 1));
        courses_to_consider = array_append(courses_to_consider, (select grades_list.course_code
                                                                 from grades_list
                                                                 where grades_list.semester = 2
                                                                   and grades_list.year = current_year - 1));
    end if;
    credits_taken = 0;
    foreach course_code in array courses_to_consider
        loop
            credits_taken = credits_taken + (select academic_data.course_catalog.credits
                                             where academic_data.course_catalog.course_code = course_code);
        end loop;
    if credits_taken = 0
    then
        return 20;  -- default credit limit
    else
        return (credits_taken * 1.25) / 2; -- calculated credit limit
    end if;
end;
$$ language plpgsql;
