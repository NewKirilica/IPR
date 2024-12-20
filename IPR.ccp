#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <random>
#include <thread>
#include <future>
#include <mutex>
#include <functional>
#include <chrono>

using namespace std;

// Класс, представляющий студента
class Student {
public:
    int Id; // Уникальный идентификатор студента
    string Name; // Имя студента
    double AverageGrade; // Средний балл студента

    // Конструктор класса Student
    Student(int id, string name, double avgGrade)
        : Id(id), Name(name), AverageGrade(avgGrade) {}

    // Метод для сериализации объекта в строку
    string Serialize() const {
        stringstream ss;
        ss << Id << "," << Name << "," << AverageGrade; // Формат строки: "Id,Имя,СреднийБал"
        return ss.str();
    }

    // Метод для десериализации объекта из строки
    static Student Deserialize(const string& data) {
        stringstream ss(data);
        int id;
        string name;
        double avgGrade;
        char delimiter;

        // Чтение данных из строки
        ss >> id >> delimiter; // Чтение Id
        getline(ss, name, ','); // Чтение имени
        ss >> avgGrade; // Чтение среднего балла

        return Student(id, name, avgGrade); // Создание объекта Student
    }
};

// Шаблонный класс StreamService для работы с потоками
template <typename T>
class StreamService {
private:
    mutex syncMutex; // Мьютекс для синхронизации потоков

public:
    // Асинхронный метод для записи данных в поток
    std::future<void> WriteToStreamAsync(ostream& stream, const vector<T>& data, function<void(string)> progress) {
        return std::async(std::launch::async, [this, &stream, &data, progress]() {
            lock_guard<mutex> lock(syncMutex); // Блокировка мьютекса
            progress("Начало записи в поток.");
            for (size_t i = 0; i < data.size(); ++i) {
                stream << data[i].Serialize() << endl; // Запись строки в поток
                this_thread::sleep_for(chrono::milliseconds(5)); // Искусственная задержка
                progress("Прогресс: " + to_string((i + 1) * 100 / data.size()) + "%");
            }
            progress("Запись в поток завершена.");
        });
    }

    // Асинхронный метод для копирования данных из потока в файл
    std::future<void> CopyFromStreamAsync(istream& stream, const string& filename, function<void(string)> progress) {
        return std::async(std::launch::async, [this, &stream, &filename, progress]() {
            lock_guard<mutex> lock(syncMutex); // Блокировка мьютекса
            progress("Начало копирования из потока.");
            ofstream file(filename);

            if (!file) {
                throw runtime_error("Ошибка открытия файла для записи.");
            }

            string line;
            while (getline(stream, line)) {
                file << line << endl; // Запись строки в файл
                this_thread::sleep_for(chrono::milliseconds(5)); // Искусственная задержка
                progress("Прогресс: неизвестно"); // Для демонстрации
            }

            file.close();
            progress("Копирование из потока завершено.");
        });
    }

    // Асинхронный метод для вычисления статистики
    std::future<int> GetStatisticsAsync(const string& filename, function<bool(const T&)> filter) {
        return std::async(std::launch::async, [&filename, filter]() {
            ifstream file(filename);

            if (!file) {
                throw runtime_error("Ошибка открытия файла для чтения.");
            }

            int count = 0;
            string line;
            while (getline(file, line)) {
                T obj = T::Deserialize(line); // Десериализация объекта из строки
                if (filter(obj)) {
                    ++count; // Увеличение счётчика, если объект соответствует фильтру
                }
            }

            file.close();
            return count; // Возврат итогового результата
        });
    }
};

// Главная функция
int main() {
    // Создание коллекции из 1000 студентов
    vector<Student> students;
    random_device rd;
    mt19937 gen(rd());
    uniform_real_distribution<> dist(5.0, 10.0); // Генерация среднего балла в диапазоне от 5 до 10

    for (int i = 0; i < 1000; ++i) {
        students.emplace_back(i, "Student" + to_string(i), dist(gen)); // Создание объектов Student
    }

    StreamService<Student> service; // Создание экземпляра StreamService
    string filename = "students.txt"; // Имя файла для записи

    // Функция для отслеживания прогресса
    auto progress = [](string message) {
        cout << "Поток " << this_thread::get_id() << ": " << message << endl;
    };

    // Поток памяти
    stringstream memoryStream;

    // Запуск задач
    auto writeTask = service.WriteToStreamAsync(memoryStream, students, progress); // Задача записи
    this_thread::sleep_for(chrono::milliseconds(200)); // Задержка перед началом копирования
    auto copyTask = service.CopyFromStreamAsync(memoryStream, filename, progress); // Задача копирования

    writeTask.wait(); // Ожидание завершения записи
    copyTask.wait(); // Ожидание завершения копирования

    // Подсчёт статистики
    auto statsTask = service.GetStatisticsAsync(filename, [](const Student& s) {
        return s.AverageGrade > 9.0; // Условие фильтра: средний балл больше 9
    });

    int result = statsTask.get(); // Получение результата статистики
    cout << "Количество студентов со средним баллом > 9: " << result << endl;

    return 0;
}
